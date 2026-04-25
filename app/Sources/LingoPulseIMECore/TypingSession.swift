/// Tracks the text buffer accumulated during a single typing session.
/// A session starts on `activateServer` and resets when the user commits
/// (Enter), cancels (Escape), navigates away (arrow keys), or deletes backward.
public struct TypingSession {
    public private(set) var buffer: String = ""

    public init() {}

    /// Append a printable string fragment (one or more characters) to the buffer.
    public mutating func append(_ text: String) {
        buffer += text
    }

    /// Clear the buffer. Called on Enter, Escape, arrow keys, and Backspace.
    public mutating func reset() {
        buffer = ""
    }

    public var isEmpty: Bool { buffer.isEmpty }
    public var wordCount: Int { buffer.split(separator: " ").count }
}
