import Foundation

enum OllamaError: Error, Equatable {
    case busy
    case timeout
    case http(Int)
    case decode(String)
    case underlying(String)
}

enum OllamaBackend { case ollama, openai }

@MainActor
final class OllamaService {
    private let backend: OllamaBackend
    private let host: String
    private let session: URLSession
    private var inFlight: Bool = false

    init(backend: OllamaBackend = .ollama, host: String = "http://127.0.0.1:11434", session: URLSession = .shared) {
        self.backend = backend
        self.host = host
        self.session = session
    }

    func generate(
        model: String,
        prompt: String,
        keepAlive: String = "30m",
        format: String? = nil,
        timeout: TimeInterval = 15.0,
        think: Bool = false,
        options: [String: Any]? = nil
    ) async throws -> String {
        guard !inFlight else { throw OllamaError.busy }
        inFlight = true
        defer { inFlight = false }

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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await withCheckedThrowingContinuation { continuation in
                session.dataTask(with: request) { d, r, e in
                    if let e {
                        continuation.resume(throwing: e)
                    } else {
                        continuation.resume(returning: (d ?? Data(), r!))
                    }
                }.resume()
            }
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw OllamaError.timeout
        } catch {
            throw OllamaError.underlying(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw OllamaError.http(httpResponse.statusCode)
        }

        do {
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
        } catch let ollamaErr as OllamaError {
            throw ollamaErr
        } catch {
            throw OllamaError.decode(error.localizedDescription)
        }
    }

    private func buildRequest(
        model: String,
        prompt: String,
        keepAlive: String,
        format: String?,
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
            if format == "json" {
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
