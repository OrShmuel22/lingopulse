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
}
