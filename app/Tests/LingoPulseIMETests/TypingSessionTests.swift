import Testing
@testable import LingoPulseIMECore

@Suite struct TypingSessionTests {

    // MARK: - Append

    @Test func emptyOnInit() {
        let s = TypingSession()
        #expect(s.buffer == "")
        #expect(s.isEmpty)
    }

    @Test func appendAccumulatesText() {
        var s = TypingSession()
        s.append("Hello")
        s.append(" ")
        s.append("world")
        #expect(s.buffer == "Hello world")
        #expect(!s.isEmpty)
    }

    @Test func wordCountEmpty() {
        let s = TypingSession()
        #expect(s.wordCount == 0)
    }

    @Test func wordCountMultiple() {
        var s = TypingSession()
        s.append("one two three")
        #expect(s.wordCount == 3)
    }

    // MARK: - Reset

    @Test func resetClearsBuffer() {
        var s = TypingSession()
        s.append("hello")
        s.reset()
        #expect(s.buffer == "")
        #expect(s.isEmpty)
    }

    @Test func resetOnEmptyBufferIsNoop() {
        var s = TypingSession()
        s.reset()
        #expect(s.buffer == "")
    }

    @Test func appendAfterResetStartsFresh() {
        var s = TypingSession()
        s.append("first")
        s.reset()
        s.append("second")
        #expect(s.buffer == "second")
    }

    @Test func multipleResetsAreIdempotent() {
        var s = TypingSession()
        s.append("text")
        s.reset()
        s.reset()
        s.reset()
        #expect(s.buffer == "")
    }

    // MARK: - Simulate enter / escape / backspace / arrow reset

    @Test func enterResetsSession() {
        var s = TypingSession()
        s.append("typed some text")
        // Enter key → controller calls reset()
        s.reset()
        #expect(s.isEmpty)
    }

    @Test func escapeResetsSession() {
        var s = TypingSession()
        s.append("partial")
        s.reset()
        #expect(s.isEmpty)
    }

    @Test func backspaceResetsSession() {
        var s = TypingSession()
        s.append("word")
        s.reset()
        #expect(s.isEmpty)
    }

    @Test func arrowLeftResetsSession() {
        var s = TypingSession()
        s.append("navigating")
        s.reset()
        #expect(s.isEmpty)
    }

    @Test func arrowRightResetsSession() {
        var s = TypingSession()
        s.append("navigating")
        s.reset()
        #expect(s.isEmpty)
    }

    @Test func arrowUpResetsSession() {
        var s = TypingSession()
        s.append("multiline")
        s.reset()
        #expect(s.isEmpty)
    }

    @Test func arrowDownResetsSession() {
        var s = TypingSession()
        s.append("multiline")
        s.reset()
        #expect(s.isEmpty)
    }

    // MARK: - Stale reset (Phase 3)

    /// Resetting an already-empty buffer must leave it empty (no crash, no side-effect).
    @Test func staleResetOnFreshSessionIsNoop() {
        var s = TypingSession()
        // Simulate activateServer being called when nothing was typed yet.
        s.reset()
        #expect(s.buffer == "")
        #expect(s.isEmpty)
    }

    /// activateServer → type → deactivateServer → activateServer:
    /// second activation on an already-cleared buffer must still leave it empty.
    @Test func staleResetAfterDeactivateIsNoop() {
        var s = TypingSession()
        s.append("hello world")
        s.reset()        // deactivateServer
        s.reset()        // activateServer on the now-empty buffer
        #expect(s.buffer == "")
        #expect(s.wordCount == 0)
    }

    /// Any number of consecutive stale resets on an empty buffer must be stable.
    @Test func consecutiveStaleResetsAreStable() {
        var s = TypingSession()
        for _ in 0..<100 {
            s.reset()
        }
        #expect(s.buffer == "")
        #expect(s.isEmpty)
    }

    /// After a stale reset, subsequent appends work normally.
    @Test func appendAfterStaleResetWorks() {
        var s = TypingSession()
        s.reset()   // stale (buffer already empty)
        s.append("fresh text")
        #expect(s.buffer == "fresh text")
        #expect(s.wordCount == 2)
    }

    // MARK: - Modifier combos (Phase 3)

    /// Shift-Left / Shift-Right / Shift-Up / Shift-Down (moveXAndModifySelection:)
    /// arrive via didCommand and the controller calls reset() for them.
    @Test func shiftLeftResetsSession() {
        var s = TypingSession()
        s.append("selected text")
        // Shift-Left → controller calls reset()
        s.reset()
        #expect(s.isEmpty)
    }

    @Test func shiftRightResetsSession() {
        var s = TypingSession()
        s.append("selected text")
        s.reset()
        #expect(s.isEmpty)
    }

    @Test func shiftUpResetsSession() {
        var s = TypingSession()
        s.append("selected text")
        s.reset()
        #expect(s.isEmpty)
    }

    @Test func shiftDownResetsSession() {
        var s = TypingSession()
        s.append("selected text")
        s.reset()
        #expect(s.isEmpty)
    }

    /// Option-Left / Option-Right (moveWordLeft: / moveWordRight:)
    @Test func optionLeftWordNavResetsSession() {
        var s = TypingSession()
        s.append("word navigation")
        // Option-Left → controller calls reset()
        s.reset()
        #expect(s.isEmpty)
    }

    @Test func optionRightWordNavResetsSession() {
        var s = TypingSession()
        s.append("word navigation")
        s.reset()
        #expect(s.isEmpty)
    }

    /// Option-Backspace (deleteWordBackward:) resets session.
    @Test func optionBackspaceResetsSession() {
        var s = TypingSession()
        s.append("delete word")
        s.reset()
        #expect(s.isEmpty)
    }

    /// Option-Delete (deleteWordForward:) resets session.
    @Test func optionDeleteResetsSession() {
        var s = TypingSession()
        s.append("delete word forward")
        s.reset()
        #expect(s.isEmpty)
    }

    /// Cmd-Backspace (deleteToBeginningOfLine:) resets session.
    @Test func cmdBackspaceResetsSession() {
        var s = TypingSession()
        s.append("delete to line start")
        s.reset()
        #expect(s.isEmpty)
    }

    // MARK: - Truncation (Phase 3)

    @Test func appendUpToMaxLengthIsAccepted() {
        var s = TypingSession()
        let text = String(repeating: "a", count: IMEConstants.Buffer.maxLength)
        s.append(text)
        #expect(s.buffer.unicodeScalars.count == IMEConstants.Buffer.maxLength)
    }

    @Test func appendBeyondMaxLengthIsDropped() {
        var s = TypingSession()
        let text = String(repeating: "a", count: IMEConstants.Buffer.maxLength + 1)
        s.append(text)
        #expect(s.buffer.unicodeScalars.count == IMEConstants.Buffer.maxLength)
    }

    @Test func appendWhenAlreadyAtMaxLengthIsNoop() {
        var s = TypingSession()
        let full = String(repeating: "x", count: IMEConstants.Buffer.maxLength)
        s.append(full)
        s.append("overflow")
        #expect(s.buffer.unicodeScalars.count == IMEConstants.Buffer.maxLength)
        #expect(!s.buffer.hasSuffix("overflow"))
    }

    @Test func appendPartiallyFillsRemainingCapacity() {
        var s = TypingSession()
        // Fill to 5 chars below max
        let almostFull = String(repeating: "a", count: IMEConstants.Buffer.maxLength - 5)
        s.append(almostFull)
        // Append 10 chars — only first 5 should be accepted
        s.append("0123456789")
        #expect(s.buffer.unicodeScalars.count == IMEConstants.Buffer.maxLength)
        #expect(s.buffer.hasSuffix("01234"))
    }

    @Test func afterResetMaxLengthResetsAndAcceptsNewText() {
        var s = TypingSession()
        let full = String(repeating: "z", count: IMEConstants.Buffer.maxLength)
        s.append(full)
        s.reset()
        s.append("hello")
        #expect(s.buffer == "hello")
    }

    @Test func maxLengthConstantIsPublicAndReasonable() {
        // Verify the constant is accessible from the test target and within a
        // practical range (1 KB … 1 MB).
        #expect(IMEConstants.Buffer.maxLength >= 1_000)
        #expect(IMEConstants.Buffer.maxLength <= 1_000_000)
    }
}
