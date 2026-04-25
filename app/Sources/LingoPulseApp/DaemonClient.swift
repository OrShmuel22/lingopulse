import Foundation

struct RefineResponse: Decodable {
    let original: String
    let refined: String
    let edits: [Edit]
}

struct Edit: Decodable {
    let type: String
    let from_text: String
    let to_text: String
    let from_span: [Int]
    let to_span: [Int]
    let category: String
    let reason: String
}

struct StatusResponse: Decodable {
    let healthy: Bool
    let model: String
    let model_loaded: Bool
}

enum DaemonError: Error {
    case http(Int)
    case payload(String)
    case transport(Error)
    case decode(Error)
}

final class DaemonClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    func status() async throws -> StatusResponse {
        try await get(path: "/status")
    }

    func refine(selection: String, app: String, toneOverride: String? = nil) async throws -> RefineResponse {
        var body: [String: Any] = ["selection": selection, "app": app]
        if let tone = toneOverride { body["tone_override"] = tone }
        return try await post(path: "/refine", body: body)
    }

    // MARK: - core HTTP

    private func get<T: Decodable>(path: String) async throws -> T {
        let req = URLRequest(url: baseURL.appendingPathComponent(path))
        return try await execute(req)
    }

    private func post<T: Decodable>(path: String, body: [String: Any]) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await execute(req)
    }

    private func execute<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw DaemonError.transport(URLError(.badServerResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DaemonError.http(http.statusCode)
        }
        // Daemon wraps everything in {ok, data} or {ok:false, error}
        let envelope: Envelope<T>
        do {
            envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        } catch {
            throw DaemonError.decode(error)
        }
        if let err = envelope.error {
            throw DaemonError.payload(err)
        }
        guard let payload = envelope.data else {
            throw DaemonError.payload("missing data field")
        }
        return payload
    }
}

private struct Envelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: String?
}
