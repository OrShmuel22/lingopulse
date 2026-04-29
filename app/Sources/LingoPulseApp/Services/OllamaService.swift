import Foundation

struct OllamaModelInfo: Codable, Equatable {
    let name: String
    let size: Int64
    let parameterSize: String?
}

enum OllamaError: Error, Equatable {
    case busy
    case timeout
    case http(Int)
    case decode(String)
    case underlying(String)
    case invalidResponse
}

enum OllamaBackend { case ollama, openai }

@MainActor
final class OllamaService {
    // Exponential backoff base for retryable errors (timeout/503/429). delay = base * 2^attempt.
    private static let retryBackoffBaseMs = 300

    private let backend: OllamaBackend
    private let host: String
    private let session: URLSession
    private var inFlightModels: Set<String> = []

    init(backend: OllamaBackend = .ollama, host: String = "http://127.0.0.1:11434", session: URLSession = .shared) {
        self.backend = backend
        self.host = host
        self.session = session
    }

    func generate(
        model: String,
        prompt: String,
        keepAlive: String = "30m",
        format: Any? = nil,
        timeout: TimeInterval = 15.0,
        think: Bool = false,
        options: [String: Any]? = nil,
        maxRetries: Int = 2
    ) async throws -> String {
        guard !inFlightModels.contains(model) else { throw OllamaError.busy }
        inFlightModels.insert(model)
        defer { inFlightModels.remove(model) }

        let (url, payload) = buildRequest(model: model, prompt: prompt, keepAlive: keepAlive, format: format, think: think, options: options)

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw OllamaError.underlying(error.localizedDescription)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = timeout

        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OllamaError.invalidResponse
                }
                guard (200..<300).contains(httpResponse.statusCode) else {
                    throw OllamaError.http(httpResponse.statusCode)
                }
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let text: String?
                if backend == .openai {
                    let choices = json?["choices"] as? [[String: Any]]
                    let message = choices?.first?["message"] as? [String: Any]
                    text = message?["content"] as? String
                } else {
                    text = json?["response"] as? String
                }
                guard let result = text else {
                    throw OllamaError.decode("missing response field")
                }
                return result
            } catch let urlError as URLError where urlError.code == .timedOut {
                lastError = OllamaError.timeout
            } catch let ollamaError as OllamaError {
                lastError = ollamaError
            } catch {
                lastError = OllamaError.underlying(error.localizedDescription)
            }

            let shouldRetry: Bool = {
                guard attempt < maxRetries else { return false }
                if let oe = lastError as? OllamaError {
                    switch oe {
                    case .timeout, .http(503), .http(429): return true
                    default: return false
                    }
                }
                return false
            }()

            if shouldRetry {
                let delayMs = Self.retryBackoffBaseMs * (1 << attempt)
                Log.debug("OllamaService: retry \(attempt + 1)/\(maxRetries) after \(delayMs)ms — \(lastError!)")
                try await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }
        }
        throw lastError!
    }

    /// Streaming variant of `generate`. Reads Ollama's NDJSON response line by
    /// line and forwards each token through `onToken` as it arrives. Returns the
    /// fully accumulated string once the model emits `done: true`.
    ///
    /// Total wall-clock latency is comparable to `generate`, but a UI that
    /// renders tokens incrementally via `onToken` perceives a much shorter
    /// time-to-first-token. Callers that don't need incremental render can keep
    /// using `generate`.
    func generateStream(
        model: String,
        prompt: String,
        keepAlive: String = "30m",
        format: Any? = nil,
        timeout: TimeInterval = 30.0,
        options: [String: Any]? = nil,
        onToken: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard !inFlightModels.contains(model) else { throw OllamaError.busy }
        inFlightModels.insert(model)
        defer { inFlightModels.remove(model) }

        guard backend == .ollama else {
            throw OllamaError.underlying("generateStream only supported on the Ollama backend")
        }

        let url = URL(string: "\(host)/api/generate")!
        var payload: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "keep_alive": keepAlive,
            "stream": true,
            "think": false,
        ]
        if let format { payload["format"] = format }
        if let options { payload["options"] = options }

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw OllamaError.underlying(error.localizedDescription)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = timeout

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw OllamaError.timeout
        } catch {
            throw OllamaError.underlying(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OllamaError.http(httpResponse.statusCode)
        }

        var accumulated = ""
        do {
            for try await line in bytes.lines {
                guard !line.isEmpty,
                      let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                if let token = json["response"] as? String, !token.isEmpty {
                    accumulated += token
                    onToken(token)
                }
                if (json["done"] as? Bool) == true { break }
            }
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw OllamaError.timeout
        } catch {
            throw OllamaError.underlying(error.localizedDescription)
        }
        return accumulated
    }

    /// GET <host>/api/tags. Throws OllamaError on transport or decoding failure.
    func listModels(timeout: Double = 5.0) async throws -> [OllamaModelInfo] {
        guard let url = URL(string: "\(host)/api/tags") else {
            throw OllamaError.underlying("invalid host URL")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw OllamaError.timeout
        } catch {
            throw OllamaError.underlying(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OllamaError.http(httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw OllamaError.decode("missing models field")
        }

        return models.compactMap { dict -> OllamaModelInfo? in
            guard let name = dict["name"] as? String else { return nil }
            let size = (dict["size"] as? Int64) ?? Int64(dict["size"] as? Int ?? 0)
            let details = dict["details"] as? [String: Any]
            let paramSize = details?["parameter_size"] as? String
            return OllamaModelInfo(name: name, size: size, parameterSize: paramSize)
        }
    }

    private func buildRequest(
        model: String,
        prompt: String,
        keepAlive: String,
        format: Any?,
        think: Bool,
        options: [String: Any]?
    ) -> (URL, [String: Any]) {
        if backend == .openai {
            let url = URL(string: "\(host)/v1/chat/completions")!
            var payload: [String: Any] = [
                "model": model,
                "messages": [["role": "user", "content": prompt]],
                "stream": false,
                "max_tokens": 2048,
            ]
            if format is String, let fmt = format as? String, fmt == "json" {
                payload["response_format"] = ["type": "json_object"]
            }
            return (url, payload)
        } else {
            let url = URL(string: "\(host)/api/generate")!
            var payload: [String: Any] = [
                "model": model,
                "prompt": prompt,
                "keep_alive": keepAlive,
                "stream": false,
                "think": think,
            ]
            if let format {
                payload["format"] = format
            }
            if let options {
                payload["options"] = options
            }
            return (url, payload)
        }
    }
}
