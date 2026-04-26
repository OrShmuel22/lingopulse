import Testing
import Foundation
@testable import LingoPulseApp

@Suite struct ProtectionTests {
    @Test func roundTripPreservesText() throws {
        let original = "Hello `world` and https://example.com and ```\ncode\n```"
        let protected = Protection.protect(original)
        let restored = try Protection.restore(protected.redacted, tokens: protected.tokens)
        #expect(restored == original)
    }

    @Test func fencedCodeBlockReplaced() {
        let text = "before ```\ncode block\n``` after"
        let protected = Protection.protect(text)
        #expect(!protected.redacted.contains("```"))
        #expect(protected.tokens.count == 1)
    }

    @Test func urlReplaced() {
        let text = "visit https://example.com for info"
        let protected = Protection.protect(text)
        #expect(!protected.redacted.contains("https://"))
        #expect(protected.tokens.count == 1)
    }

    @Test func inlineCodeReplaced() {
        let text = "run `git status` here"
        let protected = Protection.protect(text)
        #expect(!protected.redacted.contains("`git status`"))
        #expect(protected.tokens.count == 1)
    }

    @Test func multipleUrlsGetUniqueTokens() {
        let text = "see https://foo.com and https://bar.com"
        let protected = Protection.protect(text)
        #expect(protected.tokens.count == 2)
        let placeholders = protected.tokens.keys.sorted()
        #expect(placeholders[0] != placeholders[1])
    }

    @Test func restoreThrowsIfPlaceholderMissing() throws {
        let original = "Hello `code`"
        let protected = Protection.protect(original)
        // Remove the placeholder from the redacted text
        let tampered = ""
        #expect(throws: ProtectionError.self) {
            try Protection.restore(tampered, tokens: protected.tokens)
        }
    }
}
