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

    @Test func emailReplaced() {
        let text = "Contact me at user.name+tag@example.co.uk for details."
        let protected = Protection.protect(text)
        #expect(!protected.redacted.contains("@example.co.uk"))
        #expect(protected.tokens.count == 1)
        let restored = try? Protection.restore(protected.redacted, tokens: protected.tokens)
        #expect(restored == text)
    }

    @Test func filePathReplaced() {
        let text = "Save it to /Users/me/Documents/notes.txt please."
        let protected = Protection.protect(text)
        #expect(!protected.redacted.contains("/Users/me"))
        #expect(protected.tokens.count == 1)
        let restored = try? Protection.restore(protected.redacted, tokens: protected.tokens)
        #expect(restored == text)
    }

    @Test func homePathReplaced() {
        let text = "see ~/foo/bar.swift for the change"
        let protected = Protection.protect(text)
        #expect(!protected.redacted.contains("~/foo/bar.swift"))
        #expect(protected.tokens.count == 1)
    }

    @Test func dateLikeFractionNotMistakenForPath() {
        // 1/2/2025 is a date, not a path. Lookbehind ensures we don't redact it.
        let text = "the deadline is 1/2/2025 final"
        let protected = Protection.protect(text)
        #expect(protected.tokens.count == 0)
        #expect(protected.redacted == text)
    }

    @Test func hebrewRunReplaced() {
        let text = "שלום, can you review this?"
        let protected = Protection.protect(text)
        #expect(!protected.redacted.contains("שלום"))
        #expect(protected.tokens.count == 1)
        let restored = try? Protection.restore(protected.redacted, tokens: protected.tokens)
        #expect(restored == text)
    }

    @Test func multiWordHebrewRunReplacedAsOneToken() {
        let text = "I wrote בוקר טוב in the morning"
        let protected = Protection.protect(text)
        #expect(!protected.redacted.contains("בוקר"))
        #expect(!protected.redacted.contains("טוב"))
        #expect(protected.tokens.count == 1)
    }

    @Test func mixedUntouchablesAllProtected() {
        let text = "Email me at a@b.com or visit https://x.io — code is `git status` with שלום"
        let protected = Protection.protect(text)
        #expect(protected.tokens.count == 4)
        let restored = try? Protection.restore(protected.redacted, tokens: protected.tokens)
        #expect(restored == text)
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
