import Testing
import Foundation
@testable import LingoPulseApp

@Suite struct PromptsTests {
    // MARK: - classifySelection

    @Test func helloWorldIsProse() {
        #expect(Prompts.classifySelection("hello world") == .prose)
    }

    @Test func functionBodyIsCode() {
        #expect(Prompts.classifySelection("function foo() { return 1; }") == .code)
    }

    @Test func hashCommentIsCode() {
        #expect(Prompts.classifySelection("# comment") == .code)
    }

    @Test func fencedBlockIsCode() {
        #expect(Prompts.classifySelection("```\nx\n```") == .code)
    }

    @Test func twoLinesWithKeywordsIsCode() {
        #expect(Prompts.classifySelection("const x = 5;\nlet y = 6;") == .code)
    }

    @Test func singleConstLineIsProse() {
        // "const x = 5" — 1 keyword line, ratio = 1/8 = 0.125 < 0.15 → prose (matches Python)
        #expect(Prompts.classifySelection("const x = 5") == .prose)
    }

    // MARK: - tone(forApp:selection:config:)

    @MainActor private func tempConfig() -> AppConfig {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("config-\(UUID().uuidString).json")
        return AppConfig(configURL: url)
    }

    @Test @MainActor func slackToneIsCasual() {
        let config = tempConfig()
        let result = Prompts.tone(forApp: "Slack", selection: "hello", config: config)
        #expect(result == "Casual")
    }

    @Test @MainActor func cursorWithProseSelectionIsCasual() {
        let config = tempConfig()
        let result = Prompts.tone(forApp: "Cursor", selection: "hello world", config: config)
        #expect(result == "Casual")
    }

    @Test @MainActor func cursorWithCodeSelectionIsTechnical() {
        let config = tempConfig()
        let result = Prompts.tone(forApp: "Cursor", selection: "function foo() { return 1; }", config: config)
        #expect(result == "Technical")
    }

    @Test @MainActor func unknownAppReturnsDefaultNeutral() {
        let config = tempConfig()
        let result = Prompts.tone(forApp: "Unknown", selection: "hello", config: config)
        #expect(result == "Neutral")
    }

    // MARK: - buildFixerPrompt

    // MARK: - template dispatch by tone

    @Test func grammarOnlyToneUsesStrictTemplate() {
        let prompt = Prompts.buildFixerPrompt(app: "Mail", tone: "Grammar-only", message: "test")
        // The strict template's signature phrase
        #expect(prompt.contains("Grammarly's Correctness mode"))
        #expect(prompt.contains("Make the smallest possible change"))
        // The rewrite-template phrase must not be present
        #expect(!prompt.contains("adjust the text to match the requested tone"))
    }

    @Test func nonGrammarToneUsesRewriteTemplate() {
        for tone in ["Casual", "Neutral", "Professional", "Technical"] {
            let prompt = Prompts.buildFixerPrompt(app: "Mail", tone: tone, message: "test")
            #expect(prompt.contains("You fix English errors"), "tone=\(tone) should use rewrite template")
            #expect(!prompt.contains("Grammarly's Correctness mode"), "tone=\(tone) should not use strict template")
        }
    }

    @Test func defaultTemplateForGrammarOnlyIsStrict() {
        let t = Prompts.defaultTemplate(for: "Grammar-only")
        #expect(t.contains("Grammarly's Correctness mode"))
    }

    @Test func defaultTemplateForOtherToneIsRewrite() {
        let t = Prompts.defaultTemplate(for: "Casual")
        #expect(t.contains("You fix English errors"))
    }

    @Test func buildFixerPromptSubstitutesAllPlaceholders() {
        let prompt = Prompts.buildFixerPrompt(app: "Slack", tone: "Casual", message: "hello wrold")
        #expect(prompt.contains("Slack"))
        #expect(prompt.contains("Casual"))
        #expect(prompt.contains("concise, friendly"))
        #expect(prompt.contains("hello wrold"))
        #expect(!prompt.contains("{app}"))
        #expect(!prompt.contains("{tone_name}"))
        #expect(!prompt.contains("{tone_description}"))
        #expect(!prompt.contains("{message}"))
    }
}
