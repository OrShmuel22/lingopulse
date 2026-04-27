import AppKit
import Foundation

struct SpellCorrection: Equatable {
    let original: String
    let corrected: String
    let nsRange: NSRange  // range in the original input string
}

protocol SpellChecking {
    func correct(_ text: String) -> (corrected: String, edits: [SpellCorrection])
}

final class SpellCheck: SpellChecking {
    private let checker: NSSpellChecker
    private let language: String
    private let minWordLength: Int
    private let maxEditDistance: Int

    // Matches Protection-style placeholders like ⟨⟨LP:abc123⟩⟩
    private static let protectionPlaceholderPattern = try! NSRegularExpression(
        pattern: #"^__LP_(URL|CODE|EMAIL|PATH)_\d+__$"#
    )

    init(checker: NSSpellChecker = .shared,
         language: String = "en",
         minWordLength: Int = 4,
         maxEditDistance: Int = 2) {
        self.checker = checker
        self.language = language
        self.minWordLength = minWordLength
        self.maxEditDistance = maxEditDistance
    }

    func correct(_ text: String) -> (corrected: String, edits: [SpellCorrection]) {
        guard !text.isEmpty else { return ("", []) }

        let nsText = text as NSString
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }

        var edits: [SpellCorrection] = []
        var result = text
        var offset = 0  // cumulative character shift from previous replacements
        var searchStart = 0

        while searchStart < nsText.length {
            var wordCount = 0
            let misspelled = checker.checkSpelling(
                of: text,
                startingAt: searchStart,
                language: language,
                wrap: false,
                inSpellDocumentWithTag: tag,
                wordCount: &wordCount
            )

            guard misspelled.location != NSNotFound,
                  misspelled.location + misspelled.length <= nsText.length else { break }

            let word = nsText.substring(with: misspelled) as String
            searchStart = misspelled.location + misspelled.length

            // Skip Hebrew-containing words — preserve them verbatim
            if word.unicodeScalars.contains(where: { (0x0590...0x05FF).contains(Int($0.value)) }) {
                continue
            }

            // Skip words containing digits — likely code/identifiers
            if word.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) }) {
                continue
            }

            // Skip proper nouns: mixed-case mid-word signals camelCase or brand names (iTerm, MacBook).
            // All-caps words (BEACUSE) are allowed through so case-preservation can handle them.
            let scalars = Array(word.unicodeScalars)
            let hasMidUpper = scalars.dropFirst().contains(where: { CharacterSet.uppercaseLetters.contains($0) })
            let hasLower = scalars.contains(where: { CharacterSet.lowercaseLetters.contains($0) })
            if hasMidUpper && hasLower {
                continue
            }

            if word.count < minWordLength { continue }

            // Skip Protection placeholders (__LP_URL_0__ etc.)
            if word.hasPrefix("__") { continue }
            let wordNSRange = NSRange(location: 0, length: (word as NSString).length)
            if SpellCheck.protectionPlaceholderPattern.firstMatch(in: word, range: wordNSRange) != nil {
                continue
            }

            guard let guesses = checker.guesses(
                forWordRange: misspelled,
                in: text,
                language: language,
                inSpellDocumentWithTag: tag
            ), let firstGuess = guesses.first else { continue }

            let dist = levenshtein(word.lowercased(), firstGuess.lowercased())
            if dist > maxEditDistance { continue }

            let replacement = applyCase(of: word, to: firstGuess)

            let shiftedRange = NSRange(location: misspelled.location + offset, length: misspelled.length)
            guard let swiftRange = Range(shiftedRange, in: result) else { continue }

            edits.append(SpellCorrection(original: word, corrected: replacement, nsRange: misspelled))
            result.replaceSubrange(swiftRange, with: replacement)
            offset += replacement.utf16.count - word.utf16.count
        }

        assert(edits.isEmpty == (result == text))
        return (result, edits)
    }

    // Preserve case pattern of the original word applied to the suggestion.
    private func applyCase(of original: String, to suggestion: String) -> String {
        if original == original.uppercased() && original != original.lowercased() {
            return suggestion.uppercased()
        }
        if original == original.lowercased() {
            return suggestion.lowercased()
        }
        // Title case: first char upper, rest lower
        let firstUpper = original.unicodeScalars.first.map { CharacterSet.uppercaseLetters.contains($0) } ?? false
        let restLower = original.dropFirst().allSatisfy { $0.isLowercase }
        if firstUpper && restLower {
            return suggestion.prefix(1).uppercased() + suggestion.dropFirst().lowercased()
        }
        return suggestion
    }

    private func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        let m = aChars.count, n = bChars.count
        if m == 0 { return n }
        if n == 0 { return m }
        var dp = Array(0...n)
        for i in 1...m {
            var prev = dp[0]
            dp[0] = i
            for j in 1...n {
                let temp = dp[j]
                dp[j] = aChars[i-1] == bChars[j-1] ? prev : 1 + min(prev, dp[j], dp[j-1])
                prev = temp
            }
        }
        return dp[n]
    }
}
