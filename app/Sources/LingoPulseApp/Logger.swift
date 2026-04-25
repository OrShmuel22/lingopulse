import Foundation
import os

enum LogLevel: String, CaseIterable {
    case off = "Off"
    case basic = "Basic"
    case verbose = "Verbose"

    var rank: Int {
        switch self { case .off: return 0; case .basic: return 1; case .verbose: return 2 }
    }
}

enum Log {
    private static let logger = Logger(subsystem: "com.lingopulse.app", category: "main")

    // Read directly from UserDefaults so this is safe to call from any thread/actor.
    private static var currentLevel: LogLevel {
        let raw = UserDefaults.standard.string(forKey: "lp.logLevel") ?? "Basic"
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
