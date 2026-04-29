import Foundation

enum SelectionKind { case code, prose }

enum Prompts {
    private static func compileOrTrap(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            fatalError("Invalid regex \(pattern): \(error)")
        }
    }

    static let toneDescriptions: [String: String] = [
        "Casual": "concise, friendly, conversational — keep informal phrasing the author already used; capitalize the pronoun \"I\", proper nouns, and acronyms when missing, but never strip capitals the author already wrote",
        "Neutral": "balanced clarity and grammar",
        "Technical": "precise, imperative, documentation-style, clear logic; preserve code identifiers and technical terms",
        "Professional": "polite, structured, standard business English",
        "Grammar-only": "fix grammar and spelling only; do not change tone or wording unless grammatically required",
    ]

    // Static prefix block: byte-for-byte identical across calls so Ollama can
    // reuse the KV cache. Dynamic context (app/tone/message) is appended after
    // the --- divider; only the suffix gets recomputed on cache hit.
    //
    // Used for tones that intentionally rewrite (Casual / Neutral / Professional /
    // Technical). Grammar-only uses fixerTemplateStrict instead.
    static let fixerTemplate: String = """
    You fix English errors and adjust the text to match the requested tone.
    You preserve everything else.

    Rules:
    1. Fix all unambiguous errors:
       - Spelling typos (spreate → separate, recieve → receive, freind → friend).
       - Grammar (subject-verb agreement, tense, articles, plurals, pronoun
         case, fragments, run-ons).
       - Punctuation (missing commas, periods, apostrophes).
       - Wrong-word errors (your/you're, its/it's, depend of → depend on).
       - Awkward phrasing that has no grammatical reading (e.g. "I spreate
         PR" → "I made a separate PR").
    2. Same number of sentences in output as input.
    3. If input is fully correct AND already matches the tone, output = input.
       Otherwise, fix everything you are confident about.
    4. Keep code, URLs, file paths, emails, names, technical terms, and
       non-English text (including Hebrew) byte-for-byte verbatim.
    5. Preserve regional spelling (UK vs US) — keep what the author used.
    6. Capitalization is correctness, not a tone choice.
       - ADD missing capitals: lowercase pronoun "i" → "I"; lowercase
         sentence-initial → uppercase; lowercase proper nouns / brand names
         that should be capitalized.
       - PRESERVE author-written capitals: acronyms and initialisms (PR,
         API, URL, AWS, MR, CI), product names with intentional casing
         (cycode-common, iPhone, npm), and any uppercase the author used.
       - Never lowercase something the author wrote uppercase.
    7. Match the requested tone described in the context block below, but
       only adjust phrasing — never strip capitalization or punctuation that
       was already correct, and never invent informality by removing capitals.
    8. Output the result only. No preamble, no commentary, no markdown unless
       it was in the input.

    Examples:

    Input:  who is responsible on staging?
    Output: who is responsible for staging?

    Input:  i have informations and feedbacks
    Output: I have information and feedback.

    Input:  Visit https://example.com for the docs.
    Output: Visit https://example.com for the docs.

    Input:  ok so the PR is ready for review and i updated the cycode-common i spreate PR because i want it to be more clean
    Output: OK, so the PR is ready for review and I updated cycode-common. I made a separate PR because I want it to be cleaner.

    Input:  i recieve the email yesterday and forgot to reply
    Output: I received the email yesterday and forgot to reply.

    ---
    App: {app}
    Tone: {tone_name} — {tone_description}

    Input:  {message}
    Output:
    """

    // Grammarly-style "Correctness" mode — minimum-edit, voice-preserving.
    // Used when tone == "Grammar-only" so that pure correction never accidentally
    // rewrites stylistically valid prose.
    static let fixerTemplateStrict: String = """
    You are an English copy editor in the style of Grammarly's Correctness mode.
    Your only job is to fix unambiguous errors and return the corrected text.
    You are not a rewriter, a stylist, or a coach.

    Rules (in priority order):
    1. Make the smallest possible change. Edit only spans that contain a clear
       error. Leave every other character — including spacing, line breaks, and
       capitalization — exactly as written.
    2. Preserve the author's voice, register, vocabulary, sentence rhythm, and
       level of formality. Do not "improve" phrasing that is grammatically valid.
    3. Fix only these categories: spelling, grammar (subject-verb agreement,
       tense, articles a/an/the, plurals, pronoun case, fragments, run-ons),
       punctuation, sentence-initial and proper-noun capitalization, common
       wrong-word errors (your/you're, its/it's, affect/effect, "depend of" →
       "depend on").
    4. Do NOT change tone, formality, or word choice when the original is
       grammatical. Do not rewrite idioms, slang, or deliberate informality.
    5. Preserve regional spelling (UK vs US) — keep what the author used.
    6. Keep code, URLs, file paths, emails, @mentions, #hashtags, names,
       technical terms, and non-English text (including Hebrew) byte-for-byte
       verbatim. Anything inside backticks is sacred.
    7. If the input is already correct, output = input.
    8. If you are uncertain whether something is an error, leave it alone.
    9. Output the corrected text only. No preamble, no explanation, no quotes
       around the result, no markdown unless it was in the input.

    Examples:

    Input:  i are going to store
    Output: I'm going to the store.

    Input:  We was happy with the results, but their not final yet.
    Output: We were happy with the results, but they're not final yet.

    Input:  The repository at github.com/foo/bar contains the code.
    Output: The repository at github.com/foo/bar contains the code.

    Input:  yo this thing is sick lol
    Output: yo this thing is sick lol

    Input:  Please review attached document and let me know your thought's.
    Output: Please review the attached document and let me know your thoughts.

    Input:  Run `npm intsall` then check the output.
    Output: Run `npm intsall` then check the output.

    Input:  שלום, can you review this when you has time?
    Output: שלום, can you review this when you have time?

    ---
    App: {app}
    Tone: {tone_name} — {tone_description}

    Input:  {message}
    Output:
    """

    static func classifySelection(_ text: String) -> SelectionKind {
        if text.contains("```") {
            return .code
        }

        let nonWS = text.unicodeScalars.filter { !CharacterSet.whitespaces.union(.newlines).contains($0) }
        if !nonWS.isEmpty {
            let codeCharPattern = compileOrTrap(#"[{}()\[\];=<>/|]"#)
            let matchCount = codeCharPattern.numberOfMatches(
                in: text, range: NSRange(text.startIndex..., in: text))
            if Double(matchCount) / Double(nonWS.count) > 0.15 {
                return .code
            }
        }

        let firstLine = text.drop(while: { $0.isWhitespace || $0.isNewline })
        let commentPattern = compileOrTrap(#"^(//|#|/\*|--)"#)
        let firstLineStr = String(firstLine)
        if commentPattern.firstMatch(in: firstLineStr,
                                     range: NSRange(firstLineStr.startIndex..., in: firstLineStr)) != nil {
            return .code
        }

        let keywordPattern = compileOrTrap(
            #"\b(function|const|let|var|class|import|def|return|if|else|for|while|async|await|public|private|null|None|true|false)\b"#)
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

    /// Use promptOverride as the template when non-nil; prefer toneOverrides[tone] over built-in descriptions.
    /// When no override is provided, "Grammar-only" dispatches to the strict
    /// (Grammarly-style) template; all other tones use the rewrite template.
    static func buildFixerPrompt(
        app: String,
        tone: String,
        message: String,
        promptOverride: String? = nil,
        toneOverrides: [String: String] = [:]
    ) -> String {
        let template = promptOverride ?? defaultTemplate(for: tone)
        let description = resolveToneDescription(for: tone, overrides: toneOverrides)
        return template
            .replacingOccurrences(of: "{app}", with: app)
            .replacingOccurrences(of: "{tone_name}", with: tone)
            .replacingOccurrences(of: "{tone_description}", with: description)
            .replacingOccurrences(of: "{message}", with: message)
    }

    static func defaultTemplate(for tone: String) -> String {
        tone == "Grammar-only" ? fixerTemplateStrict : fixerTemplate
    }

    static func resolveToneDescription(for toneName: String, overrides: [String: String]) -> String {
        overrides[toneName] ?? toneDescriptions[toneName] ?? toneDescriptions["Neutral"] ?? ""
    }
}
