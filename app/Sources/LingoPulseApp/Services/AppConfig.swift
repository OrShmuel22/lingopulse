import Foundation

@MainActor
final class AppConfig {
    static let shared = AppConfig()

    private(set) var values: [String: Any]
    private let configURL: URL

    private static let DEFAULTS: [String: Any] = [
        "fixer": [
            "model": "gemma3:1b-it-qat",
            "timeout_seconds": 15,
            "max_retries": 2
        ],
        "dictionary": [
            "model": "gemma3:1b-it-qat",
            "timeout_seconds": 15
        ],
        "keepalive": [
            "enabled": true,
            "ollama_keep_alive": "30m",
            "inactive_keep_alive": "5m",
            "ping_interval_minutes": 25,
            "active_hours_start": "08:00",
            "active_hours_end": "22:00",
            "login_warmup": true
        ],
        "tone": [
            "default_tone": "Neutral",
            "app_map": [
                "Slack": "Casual",
                "Discord": "Casual",
                "Mail": "Professional",
                "Outlook": "Professional",
                "Cursor": "auto",
                "Code": "auto",
                "Visual Studio Code": "auto",
                "Messages": "Casual",
                "Notes": "Neutral",
                "Linear": "Professional"
            ]
        ],
        "ring_buffer": [
            "size": 5,
            "path": "~/.cache/lingopulse/ring.json"
        ],
        "history": [
            "path": "~/.config/lingopulse/history.jsonl"
        ],
        "feedback": [
            "path": "~/.config/lingopulse/feedback.jsonl",
            "hud_show_after_ms": 100,
            "hud_cold_start_notice_after_ms": 2000,
            "hud_error_after_ms": 15000,
            "toast_duration_seconds": 5
        ],
        "personal_dict": [
            "path": "~/.config/lingopulse/personal_dict.json"
        ],
        "spell_check": [
            "enabled": true
        ]
    ]

    init(configURL: URL = AppConfig.defaultURL()) {
        self.configURL = configURL
        self.values = AppConfig.loadOrCreate(at: configURL)
    }

    nonisolated static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/lingopulse/config.json")
    }

    func value<T>(at dotPath: String, as type: T.Type = T.self) -> T? {
        let parts = dotPath.split(separator: ".").map(String.init)
        var current: Any = values
        for part in parts {
            guard let dict = current as? [String: Any], let next = dict[part] else {
                return nil
            }
            current = next
        }
        return current as? T
    }

    func path(at dotPath: String) -> URL? {
        guard let s: String = value(at: dotPath) else { return nil }
        let expanded = NSString(string: s).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    func reload() {
        values = AppConfig.loadOrCreate(at: configURL)
    }

    private static func loadOrCreate(at url: URL) -> [String: Any] {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            if let data = try? JSONSerialization.data(withJSONObject: DEFAULTS,
                                                      options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: url)
            }
            return DEFAULTS
        }
        do {
            let data = try Data(contentsOf: url)
            guard let userConfig = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                Log.error("AppConfig: failed to parse \(url.path), using defaults: top-level JSON is not an object")
                return DEFAULTS
            }
            return deepMerge(base: DEFAULTS, override: userConfig)
        } catch {
            Log.error("AppConfig: failed to parse \(url.path), using defaults: \(error)")
            return DEFAULTS
        }
    }

    private static func deepMerge(base: [String: Any], override: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in override {
            if let baseDict = result[key] as? [String: Any],
               let overrideDict = value as? [String: Any] {
                result[key] = deepMerge(base: baseDict, override: overrideDict)
            } else {
                result[key] = value
            }
        }
        return result
    }
}
