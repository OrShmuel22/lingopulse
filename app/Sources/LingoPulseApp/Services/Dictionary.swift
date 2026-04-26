import Foundation

struct DictionaryCandidate: Equatable {
    let word: String
    let example: String
    let register: String
    let confidence: String
}

enum Dictionary {
    static let hebrewRegex = try! NSRegularExpression(pattern: "[֐-׿]")

    static func detectHebrew(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return hebrewRegex.firstMatch(in: text, range: range) != nil
    }

    static let enPrompt = """
    You help a user find precise English words from a description.
    Return exactly 3 word candidates as a JSON array. For each candidate:
      "word": the English word or short phrase
      "example": one brief sentence showing the word in use
      "register": one of "casual", "neutral", "formal", "technical"
    Prefer words the user is likely looking for over archaic or obscure options.
    Preserve existing English words from the query if they're already correct.

    Query: {query}

    Return only the JSON array. No preamble.
    """

    static let hePrompt = """
    You help a native Hebrew speaker find precise English words.
    The user has typed a description that may include Hebrew, English, or both.
    Return up to 3 word candidates as a JSON array. For each:
      "word": the English word or short phrase
      "example": one brief sentence showing the word in use
      "register": one of "casual", "neutral", "formal", "technical"
      "confidence": one of "high", "low"

    Rules:
    - If you are uncertain about a translation, set confidence="low" and still include it.
    - If you would be guessing, return fewer than 3 candidates rather than padding with uncertain options.
    - Be conservative: prefer common, current words over archaic or rare ones.

    Query: {query}

    Return only the JSON array. No preamble.
    """

    static func buildPrompt(query: String) -> String {
        let template = detectHebrew(query) ? hePrompt : enPrompt
        return template.replacingOccurrences(of: "{query}", with: query)
    }

    static func parseResponse(_ raw: String) -> [DictionaryCandidate] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip leading markdown fence
        if let range = text.range(of: "^```[a-zA-Z]*\n?", options: .regularExpression) {
            text.removeSubrange(range)
        }
        // Strip trailing markdown fence
        if let range = text.range(of: "\n?```$", options: .regularExpression) {
            text.removeSubrange(range)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to extract JSON array via first [ and last ]
        if let startIdx = text.firstIndex(of: "["),
           let lastBracket = text.lastIndex(of: "]"),
           lastBracket > startIdx {
            let arrayStr = String(text[startIdx...lastBracket])
            if let data = arrayStr.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data),
               let arr = parsed as? [[String: Any]] {
                return arr.compactMap(candidateFromDict)
            }
        }

        // Regex fallback: extract individual JSON objects
        guard let objRegex = try? NSRegularExpression(pattern: "\\{[^{}]+\\}", options: .dotMatchesLineSeparators) else {
            return []
        }
        let nsText = text as NSString
        let matches = objRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.compactMap { match in
            let objStr = nsText.substring(with: match.range)
            guard let data = objStr.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data),
                  let dict = parsed as? [String: Any],
                  dict["word"] != nil else { return nil }
            return candidateFromDict(dict)
        }
    }

    private static func candidateFromDict(_ dict: [String: Any]) -> DictionaryCandidate? {
        guard let word = dict["word"] as? String else { return nil }
        return DictionaryCandidate(
            word: word,
            example: dict["example"] as? String ?? "",
            register: dict["register"] as? String ?? "",
            confidence: dict["confidence"] as? String ?? "high"
        )
    }
}
