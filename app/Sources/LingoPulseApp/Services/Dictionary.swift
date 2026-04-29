import Foundation

struct DictionaryCandidate: Equatable {
    let word: String
    let example: String
    let register: String
    let confidence: String
}

enum Dictionary {
    static let hebrewRegex = compileOrTrap("[֐-׿]")

    private static func compileOrTrap(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            fatalError("Invalid regex \(pattern): \(error)")
        }
    }

    static func detectHebrew(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return hebrewRegex.firstMatch(in: text, range: range) != nil
    }

    static let jsonSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "candidates": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "word": ["type": "string"],
                        "example": ["type": "string"],
                        "register": ["type": "string", "enum": ["casual", "neutral", "formal", "technical"]],
                        "confidence": ["type": "string", "enum": ["high", "low"]]
                    ],
                    "required": ["word"]
                ]
            ]
        ],
        "required": ["candidates"]
    ]

    static let enPrompt = """
    You help a user find precise English words from a description.
    Return a JSON object with a "candidates" array containing up to 3 word candidates.
    For each candidate:
      "word": the English word or short phrase
      "example": one brief sentence showing the word in use
      "register": one of "casual", "neutral", "formal", "technical"
      "confidence": one of "high", "low"
    Prefer words the user is likely looking for over archaic or obscure options.
    Preserve existing English words from the query if they're already correct.
    If the query refers to a term you do not recognize (e.g. very recent slang
    or specialized jargon you are not confident about), return fewer candidates
    or an empty list rather than inventing definitions.

    Query: {query}

    Return only the JSON object. No preamble. No markdown fences.
    """

    static let hePrompt = """
    You help a native Hebrew speaker find precise English words.
    The user has typed a description that may include Hebrew, English, or both.
    Return a JSON object with a "candidates" array containing up to 3 word candidates.
    For each:
      "word": the English word or short phrase
      "example": one brief sentence showing the word in use
      "register": one of "casual", "neutral", "formal", "technical"
      "confidence": one of "high", "low"

    Rules:
    - If you are uncertain about a translation, set confidence="low" and still include it.
    - If you would be guessing, return fewer than 3 candidates rather than padding with uncertain options.
    - Be conservative: prefer common, current words over archaic or rare ones.
    - If a Hebrew or English term is unfamiliar to you (e.g. very recent slang
      or specialized jargon you are not confident about), return fewer or zero
      candidates rather than inventing definitions.

    Query: {query}

    Return only the JSON object. No preamble. No markdown fences.
    """

    static func buildPrompt(query: String) -> String {
        let template = detectHebrew(query) ? hePrompt : enPrompt
        return template.replacingOccurrences(of: "{query}", with: query)
    }

    static func parseResponse(_ raw: String) -> [DictionaryCandidate] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let range = text.range(of: "^```[a-zA-Z]*\\n?", options: .regularExpression) {
            text.removeSubrange(range)
        }
        if let range = text.range(of: "\\n?```$", options: .regularExpression) {
            text.removeSubrange(range)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]] else {
            return []
        }

        return candidates.compactMap(candidateFromDict)
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
