import Foundation

struct ProtectedText: Equatable {
    let redacted: String
    let tokens: [String: String]
}

enum ProtectionError: Error {
    case placeholderMissing(String)
}

enum Protection {
    private static let patterns: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"```[\s\S]*?```"#),
        try! NSRegularExpression(pattern: #"https?://\S+"#),
        try! NSRegularExpression(pattern: #"`[^`\n]+`"#),
    ]

    static func protect(_ text: String) -> ProtectedText {
        var tokens: [String: String] = [:]
        var result = text

        for pattern in patterns {
            var output = ""
            var lastEnd = result.startIndex

            let nsResult = result as NSString
            let fullRange = NSRange(location: 0, length: nsResult.length)
            let matches = pattern.matches(in: result, range: fullRange)

            for match in matches {
                guard let swiftRange = Range(match.range, in: result) else { continue }
                output += result[lastEnd..<swiftRange.lowerBound]
                let original = String(result[swiftRange])
                let placeholder = "⟨⟨LP:\(randomHex())⟩⟩"
                tokens[placeholder] = original
                output += placeholder
                lastEnd = swiftRange.upperBound
            }
            output += result[lastEnd...]
            result = output
        }

        return ProtectedText(redacted: result, tokens: tokens)
    }

    static func restore(_ text: String, tokens: [String: String]) throws -> String {
        var result = text
        for (placeholder, original) in tokens {
            guard result.contains(placeholder) else {
                throw ProtectionError.placeholderMissing(placeholder)
            }
            result = result.replacingOccurrences(of: placeholder, with: original)
        }
        return result
    }

    private static func randomHex() -> String {
        var rng = SystemRandomNumberGenerator()
        let b0 = UInt8.random(in: 0...255, using: &rng)
        let b1 = UInt8.random(in: 0...255, using: &rng)
        let b2 = UInt8.random(in: 0...255, using: &rng)
        return String(format: "%02x%02x%02x", b0, b1, b2)
    }
}
