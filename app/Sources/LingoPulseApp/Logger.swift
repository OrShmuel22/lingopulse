import Foundation
import os

typealias OSLogger = Logger

enum LogLevel: String, CaseIterable {
    case off = "Off"
    case basic = "Basic"
    case verbose = "Verbose"

    var rank: Int {
        switch self { case .off: return 0; case .basic: return 1; case .verbose: return 2 }
    }
}

enum Log {
    static let logger = OSLogger(subsystem: "com.lingopulse.app", category: "main")
    private static var cachedLevelRaw: String = "Basic"
    private static let levelLock = NSLock()

    static func setLevel(_ raw: String) {
        levelLock.withLock { cachedLevelRaw = raw }
    }

    static var currentLevel: LogLevel {
        let raw = levelLock.withLock { cachedLevelRaw }
        return LogLevel(rawValue: raw) ?? .basic
    }

    static func info(_ message: String) {
        guard currentLevel.rank >= LogLevel.basic.rank else { return }
        logger.info("LingoPulse: \(message, privacy: .public)")
    }

    static func debug(_ message: String) {
        guard currentLevel.rank >= LogLevel.verbose.rank else { return }
        logger.debug("LingoPulse: \(message, privacy: .public)")
    }

    static func error(_ message: String) {
        guard currentLevel.rank >= LogLevel.basic.rank else { return }
        logger.error("LingoPulse: \(message, privacy: .public)")
    }
}
