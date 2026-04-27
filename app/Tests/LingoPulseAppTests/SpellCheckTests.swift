import Testing
import Foundation
@testable import LingoPulseApp

// These tests run against the real NSSpellChecker (macOS system dictionary).
// Expected outputs are locked to observed behavior on the test runner.

@Suite struct SpellCheckTests {

    // 1. Single typo: beacuse -> because
    @Test func singleTypoBeacuse() {
        let spell = SpellCheck()
        let (corrected, edits) = spell.correct("beacuse")
        #expect(corrected == "because")
        #expect(edits.count == 1)
        #expect(edits[0].original == "beacuse")
        #expect(edits[0].corrected == "because")
    }

    // 2. Single typo: annoing -> annoying
    @Test func singleTypoAnnoing() {
        let spell = SpellCheck()
        let (corrected, edits) = spell.correct("annoing")
        #expect(corrected == "annoying")
        #expect(edits.count == 1)
        #expect(edits[0].original == "annoing")
        #expect(edits[0].corrected == "annoying")
    }

    // 3. Mixed sentence: only the typo is corrected, real words are untouched
    @Test func mixedSentenceOnlyTypoCorrected() {
        let spell = SpellCheck()
        let (corrected, edits) = spell.correct("it varies annoing")
        #expect(corrected == "it varies annoying")
        #expect(edits.count == 1)
        #expect(edits[0].original == "annoing")
        #expect(edits[0].corrected == "annoying")
    }

    // 4. Multi-typo sentence.
    //
    // Observed NSSpellChecker behavior (sentence context matters for guesses):
    //   "beacuse"  -> "because"  (dist 2, corrected)
    //   "selectt"  -> "select"   (dist 1, corrected)
    //   "iterm"    -> "term"     (dist 1, corrected — lowercase word, no uppercase mid-word)
    //   "anoying"  -> "annoying" (dist 1, corrected)
    //
    // NOTE: lowercase "iterm" has no uppercase mid-word signal, so the proper-noun
    // guard does NOT apply. It is treated as a plain misspelled word. In sentence
    // context NSSpellChecker suggests "term" (not "item"); both are within dist 2.
    @Test func multiTypoSentence() {
        let spell = SpellCheck()
        let input = "we beacuse selectt the iterm so anoying"
        let (corrected, edits) = spell.correct(input)
        // All four misspellings must be corrected
        #expect(edits.count == 4)
        #expect(corrected.contains("because"))
        #expect(corrected.contains("select"))
        #expect(corrected.contains("anoying") == false)
        // "iterm" is corrected to "term" in sentence context
        #expect(corrected.contains("iterm") == false)
    }

    // 5. Hebrew skip: Hebrew word is left verbatim, English typo is corrected
    @Test func hebrewWordSkipped() {
        let spell = SpellCheck()
        let (corrected, edits) = spell.correct("שלום beacuse")
        #expect(corrected == "שלום because")
        #expect(edits.count == 1)
        #expect(edits[0].original == "beacuse")
    }

    // 6. Protection placeholder skip (__LP_URL_0__ format)
    @Test func protectionPlaceholderSkipped() {
        let spell = SpellCheck()
        let (corrected, edits) = spell.correct("__LP_URL_0__ beacuse")
        #expect(corrected == "__LP_URL_0__ because")
        #expect(edits.count == 1)
        #expect(edits[0].original == "beacuse")
    }

    // 7. Word containing digits is skipped
    @Test func digitWordSkipped() {
        let spell = SpellCheck()
        let (corrected, edits) = spell.correct("abc123def beacuse")
        #expect(corrected == "abc123def because")
        #expect(edits.count == 1)
        #expect(edits[0].original == "beacuse")
    }

    // 8. Words shorter than minWordLength (default 4) are not corrected
    @Test func shortWordsSkipped() {
        let spell = SpellCheck()
        let (corrected, edits) = spell.correct("i ok beacuse")
        #expect(corrected == "i ok because")
        // "i" (len 1) and "ok" (len 2) are below minWordLength=4; untouched
        let originals = edits.map { $0.original }
        #expect(!originals.contains("i"))
        #expect(!originals.contains("ok"))
        #expect(edits.count == 1)
    }

    // 9. Empty input returns empty result
    @Test func emptyInput() {
        let spell = SpellCheck()
        let (corrected, edits) = spell.correct("")
        #expect(corrected == "")
        #expect(edits.isEmpty)
    }

    // 10. Case preservation
    @Test func casePreservationTitleCase() {
        let spell = SpellCheck()
        let (corrected, edits) = spell.correct("Beacuse")
        #expect(corrected == "Because")
        #expect(edits.count == 1)
        #expect(edits[0].corrected == "Because")
    }

    @Test func casePreservationAllCaps() {
        let spell = SpellCheck()
        let (corrected, edits) = spell.correct("BEACUSE")
        #expect(corrected == "BECAUSE")
        #expect(edits.count == 1)
        #expect(edits[0].corrected == "BECAUSE")
    }

    // 11. Idempotency: corrected output produces zero edits
    @Test func idempotentAfterCorrection() {
        let spell = SpellCheck()
        let (first, _) = spell.correct("beacuse annoing")
        let (second, edits2) = spell.correct(first)
        #expect(edits2.isEmpty)
        #expect(second == first)
    }

    // 12. edits[i].nsRange matches the original word in the input string
    @Test func nsRangeMatchesOriginalWord() {
        let spell = SpellCheck()
        let input = "it beacuse works"
        let (_, edits) = spell.correct(input)
        #expect(edits.count == 1)
        let edit = edits[0]
        let nsInput = input as NSString
        let slice = nsInput.substring(with: edit.nsRange)
        #expect(slice == edit.original)
    }
}
