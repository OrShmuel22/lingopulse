import Foundation

struct Edit: Decodable {
    let type: String
    let from_text: String
    let to_text: String
    let from_span: [Int]
    let to_span: [Int]
    let category: String
    let reason: String
    let confidence: String  // "high" | "medium" | "low"
    let risk: String        // "safe" | "risky"

    var categoryEnum: EditCategory { EditCategory(rawValue: category) ?? .other }
    var confidenceEnum: Confidence { Confidence(rawValue: confidence) ?? .low }
    var riskEnum: Risk { Risk(rawValue: risk) ?? .safe }

    // Backward-compatible coding keys so older payloads without these fields default gracefully
    private enum CodingKeys: String, CodingKey {
        case type, from_text, to_text, from_span, to_span, category, reason, confidence, risk
    }

    init(from decoder: Decoder) throws {
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

enum Envelope<T: Decodable>: Decodable {
    case success(T)
    case failure(String)

    private struct Raw: Decodable {
        let ok: Bool
        let data: T?
        let error: String?
    }

    init(from decoder: Decoder) throws {
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
