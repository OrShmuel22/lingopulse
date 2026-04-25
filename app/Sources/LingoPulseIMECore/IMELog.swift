import Foundation
import os

public enum IMELog {
    public static let logger = Logger(subsystem: "com.lingopulse.ime", category: "main")

    public static func info(_ message: String) {
        logger.info("LingoPulseIME: \(message, privacy: .public)")
    }

    public static func debug(_ message: String) {
        logger.debug("LingoPulseIME: \(message, privacy: .public)")
    }

    public static func error(_ message: String) {
        logger.error("LingoPulseIME: \(message, privacy: .public)")
    }
}
