/// Tracks the text buffer accumulated during a single typing session.
/// A session starts on `activateServer` and resets when the user commits
/// (Enter), cancels (Escape), navigates away (arrow keys), or deletes backward.
public struct TypingSession {
    public private(set) var buffer: String = ""

    public init() {}

    /// Append a printable string fragment (one or more characters) to the buffer.
    /// Characters that would push the buffer past `IMEConstants.Buffer.maxLength`
    /// Unicode scalars are silently dropped to prevent unbounded growth.
    public mutating func append(_ text: String) {
        let remaining = IMEConstants.Buffer.maxLength - buffer.unicodeScalars.count
        guard remaining > 0 else { return }
        if text.unicodeScalars.count <= remaining {
            buffer += text
        } else {
            let truncated = String(text.unicodeScalars.prefix(remaining))
            buffer += truncated
        }
    }

    /// Clear the buffer. Called on Enter, Escape, arrow keys, Backspace,
    /// modifier combos (Cmd+A, Cmd+Z, etc.), and focus changes.
    /// Safe to call on an already-empty buffer (no-op).
    public mutating func reset() {
        buffer = ""
    }

    public var isEmpty: Bool { buffer.isEmpty }
    public var wordCount: Int { buffer.split(separator: " ").count }
}
