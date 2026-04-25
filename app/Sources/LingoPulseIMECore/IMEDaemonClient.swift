import Foundation

// Duplicated from main app's DaemonClient.swift.
// Shared module planned for Phase 10 (polish).

public struct IMEEdit: Decodable {
    public let type: String
    public let from_text: String
    public let to_text: String
    public let from_span: [Int]
    public let to_span: [Int]
    public let category: String
    public let reason: String
    public let confidence: String  // "high" | "medium" | "low"
    public let risk: String        // "safe" | "risky"

    private enum CodingKeys: String, CodingKey {
        case type, from_text, to_text, from_span, to_span, category, reason, confidence, risk
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        from_text = try c.decode(String.self, forKey: .from_text)
        to_text = try c.decode(String.self, forKey: .to_text)
        from_span = try c.decode([Int].self, forKey: .from_span)
        to_span = try c.decode([Int].self, forKey: .to_span)
        category = try c.decode(String.self, forKey: .category)
        reason = try c.decode(String.self, forKey: .reason)
        confidence = try c.decodeIfPresent(String.self, forKey: .confidence) ?? "low"
        risk = try c.decodeIfPresent(String.self, forKey: .risk) ?? "safe"
    }
}

public struct IMERefineResponse: Decodable {
    public let original: String
    public let refined: String
    public let edits: [IMEEdit]
}

public enum IMEEnvelope<T: Decodable>: Decodable {
    case success(T)
    case failure(String)

    private struct Raw: Decodable {
        let ok: Bool
        let data: T?
        let error: String?
    }

    public init(from decoder: Decoder) throws {
        let raw = try Raw(from: decoder)
        if raw.ok, let data = raw.data {
            self = .success(data)
        } else if !raw.ok, let error = raw.error {
            self = .failure(error)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid envelope: ok=\(raw.ok), data=\(raw.data == nil ? "nil" : "present"), error=\(raw.error ?? "nil")"
            ))
        }
    }
}

public enum IMEDaemonError: Error {
    case http(Int)
    case payload(String)
    case transport(Error)
    case decode(Error)
}

public struct IMEApplyEditsResponse: Decodable {
    public let original: String
    public let refined: String
    public let edits: [IMEEdit]
}

public final class IMEDaemonClient {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "http://127.0.0.1:17823")!) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    public func refine(text: String, app: String) async throws -> IMERefineResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("/refine"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["selection": text, "app": app]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw IMEDaemonError.transport(URLError(.badServerResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw IMEDaemonError.http(http.statusCode)
        }
        let envelope: IMEEnvelope<IMERefineResponse>
        do {
            envelope = try JSONDecoder().decode(IMEEnvelope<IMERefineResponse>.self, from: data)
        } catch {
            throw IMEDaemonError.decode(error)
        }
        switch envelope {
        case .success(let payload): return payload
        case .failure(let msg): throw IMEDaemonError.payload(msg)
        }
    }

    /// Apply a subset of edits to the original text and return the resulting
    /// text plus remaining edits.  `indices` is the 0-based set of edits to
    /// apply; omitting an index leaves that edit unresolved.
    public func applyEdits(original: String,
                           edits: [IMEEdit],
                           indices: [Int]) async throws -> IMEApplyEditsResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("/apply_edits"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Serialise edits manually since IMEEdit is Decodable-only.
        let editsJSON: [[String: Any]] = edits.map { e in
            ["type": e.type,
             "from_text": e.from_text,
             "to_text": e.to_text,
             "from_span": e.from_span,
             "to_span": e.to_span,
             "category": e.category,
             "reason": e.reason,
             "confidence": e.confidence,
             "risk": e.risk]
        }
        let body: [String: Any] = [
            "original": original,
            "edits": editsJSON,
            "indices": indices
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw IMEDaemonError.transport(URLError(.badServerResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw IMEDaemonError.http(http.statusCode)
        }
        let envelope: IMEEnvelope<IMEApplyEditsResponse>
        do {
            envelope = try JSONDecoder().decode(IMEEnvelope<IMEApplyEditsResponse>.self, from: data)
        } catch {
            throw IMEDaemonError.decode(error)
        }
        switch envelope {
        case .success(let payload): return payload
        case .failure(let msg): throw IMEDaemonError.payload(msg)
        }
    }
}
