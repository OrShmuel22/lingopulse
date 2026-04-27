import Testing
import Foundation
@testable import LingoPulseApp

@Suite struct PromptsOverrideTests {

    // MARK: promptOverride

    @Test func promptOverrideUsedAsTemplate() {
        let custom = "Custom: {app} {tone_name} {tone_description} {message}"
        let result = Prompts.buildFixerPrompt(
            app: "Slack",
            tone: "Casual",
            message: "hi",
            promptOverride: custom
        )
        #expect(result == "Custom: Slack Casual concise, friendly, lowercase allowed, minimal punctuation hi")
        // Must NOT contain any un-substituted placeholders
        #expect(!result.contains("{app}"))
        #expect(!result.contains("{message}"))
    }

    @Test func nilPromptOverrideFallsBackToDefault() {
        let result = Prompts.buildFixerPrompt(
            app: "Slack",
            tone: "Casual",
            message: "hello",
            promptOverride: nil
        )
        // Default fixerTemplate contains "You fix English errors"
        #expect(result.contains("You fix English errors"))
    }

    // MARK: toneOverrides

    @Test func toneOverridePreferredOverDefault() {
        let result = Prompts.buildFixerPrompt(
            app: "Slack",
            tone: "Casual",
            message: "yo",
            toneOverrides: ["Casual": "extra-casual vibe"]
        )
        #expect(result.contains("extra-casual vibe"))
        // The built-in casual description must NOT appear
        #expect(!result.contains("concise, friendly"))
    }

    @Test func emptyToneOverridesUsesDefault() {
        let result = Prompts.buildFixerPrompt(
            app: "Slack",
            tone: "Casual",
            message: "yo",
            toneOverrides: [:]
        )
        #expect(result.contains("concise, friendly"))
    }

    @Test func unknownToneWithOverrideFallsBackToNeutral() {
        // "FancyTone" not in defaults; no override provided → falls back to Neutral description
        let result = Prompts.buildFixerPrompt(
            app: "Mail",
            tone: "FancyTone",
            message: "test",
            toneOverrides: [:]
        )
        let neutralDesc = Prompts.toneDescriptions["Neutral"] ?? ""
        #expect(result.contains(neutralDesc))
    }

    // MARK: resolveToneDescription

    @Test func resolvePrefersOverride() {
        let desc = Prompts.resolveToneDescription(for: "Casual", overrides: ["Casual": "super chill"])
        #expect(desc == "super chill")
    }

    @Test func resolveFallsBackToBuiltIn() {
        let desc = Prompts.resolveToneDescription(for: "Casual", overrides: [:])
        #expect(desc == Prompts.toneDescriptions["Casual"])
    }

    @Test func resolveUnknownToneFallsBackToNeutral() {
        let desc = Prompts.resolveToneDescription(for: "Nonexistent", overrides: [:])
        #expect(desc == Prompts.toneDescriptions["Neutral"])
    }
}
