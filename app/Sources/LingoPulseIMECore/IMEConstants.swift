import Foundation

public enum IMEConstants {
    public enum Buffer {
        /// Maximum number of Unicode scalars the session buffer may hold.
        /// Characters appended beyond this limit are silently dropped to
        /// prevent unbounded memory growth in long dictation sessions.
        public static let maxLength: Int = 10_000
    }
}
