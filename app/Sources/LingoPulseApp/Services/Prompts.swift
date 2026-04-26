import Foundation

enum SelectionKind { case code, prose }

enum Prompts {
    static let toneDescriptions: [String: String] = [
        "Casual": "concise, friendly, lowercase allowed, minimal punctuation",
        "Neutral": "balanced clarity and grammar",
        "Technical": "precise, imperative, documentation-style, clear logic; preserve code identifiers and technical terms",
        "Professional": "polite, structured, standard business English",
        "Grammar-only": "fix grammar and spelling only; do not change tone or wording unless grammatically required",
    ]

    static let fixerTemplate: String = """
    You fix English errors. You preserve everything else.

    Rules:
    1. Same number of sentences in output as input.
    2. If input is correct, output = input. Do not rephrase clean text.
    3. Keep code, URLs, names, technical terms, and Hebrew text verbatim.
    4. Match the original tone — {tone_description}.

    App: {app}
    Tone: {tone_name}

    Examples:

    Input:  who is responsible on staging?
    Output: who is responsible for staging?

    Input:  i have informations and feedbacks
    Output: i have information and feedback

    Input:  Ok, I've tested the app; there are small fixes.
    Output: Ok, I've tested the app; there are small fixes.

    Input:  {message}
    Output:
    """

    static func classifySelection(_ text: String) -> SelectionKind {
        if text.contains("```") {
            return .code
        }

        let nonWS = text.unicodeScalars.filter { !CharacterSet.whitespaces.union(.newlines).contains($0) }
        if !nonWS.isEmpty {
            let codeCharPattern = try! NSRegularExpression(pattern: #"[{}()\[\];=<>/|]"#)
            let matchCount = codeCharPattern.numberOfMatches(
                in: text, range: NSRange(text.startIndex..., in: text))
            if Double(matchCount) / Double(nonWS.count) > 0.15 {
                return .code
            }
        }

        let firstLine = text.drop(while: { $0.isWhitespace || $0.isNewline })
        let commentPattern = try! NSRegularExpression(pattern: #"^(//|#|/\*|--)"#)
        let firstLineStr = String(firstLine)
        if commentPattern.firstMatch(in: firstLineStr,
                                     range: NSRange(firstLineStr.startIndex..., in: firstLineStr)) != nil {
            return .code
        }

        let keywordPattern = try! NSRegularExpression(
            pattern: #"\b(function|const|let|var|class|import|def|return|if|else|for|while|async|await|public|private|null|None|true|false)\b"#)
        var linesWithKeywords = Set<Int>()
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        keywordPattern.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let charIndex = match.range.location
            let prefix = nsText.substring(to: charIndex)
            let lineNum = prefix.components(separatedBy: "\n").count - 1
            linesWithKeywords.insert(lineNum)
        }
        if linesWithKeywords.count >= 2 {
            return .code
        }

        return .prose
    }

    @MainActor
    static func tone(forApp app: String, selection: String, config: AppConfig) -> String {
        let appMap: [String: String] = config.value(at: "tone.app_map") ?? [:]
        let defaultTone: String = config.value(at: "tone.default_tone") ?? "Neutral"

        let tone = appMap[app] ?? defaultTone

        if tone == "auto" {
            let kind = classifySelection(selection)
            return kind == .code ? "Technical" : "Casual"
        }

        return tone
    }

    static func buildFixerPrompt(app: String, tone: String, message: String) -> String {
        let description = toneDescriptions[tone] ?? "balanced clarity and grammar"
        return fixerTemplate
            .replacingOccurrences(of: "{app}", with: app)
            .replacingOccurrences(of: "{tone_name}", with: tone)
            .replacingOccurrences(of: "{tone_description}", with: description)
            .replacingOccurrences(of: "{message}", with: message)
    }
}
