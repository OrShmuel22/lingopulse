import Foundation
import Combine
import ServiceManagement

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    /// App Group suite. Falls back to UserDefaults.standard if the group
    /// container is unavailable (e.g. during unit tests running outside a
    /// signed app context).
    static let appGroupID = "group.com.lingopulse.shared"

    private let defaults: UserDefaults = {
        UserDefaults(suiteName: Preferences.appGroupID) ?? .standard
    }()

    private enum Key {
        static let enabled = "lp.enabled"
        static let daemonURL = "lp.daemon.url"
        static let excludedApps = "lp.excludedApps"
        static let debounceSeconds = "lp.debounceSeconds"
        static let autoDismissSeconds = "lp.autoDismissSeconds"
        static let logLevel = "lp.logLevel"
        static let onboardingCompleted = "lp.onboardingCompleted"
        static let launchAtLogin = "lp.launchAtLogin"
    }

    static let defaultExcludedApps: Set<String> = [
        "iTerm2", "Terminal", "Alacritty", "WezTerm", "Hyper", "Warp"
    ]

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
    }
    @Published var daemonURL: String {
        didSet { defaults.set(daemonURL, forKey: Key.daemonURL) }
    }
    @Published var excludedApps: Set<String> {
        didSet { defaults.set(Array(excludedApps), forKey: Key.excludedApps) }
    }
    @Published var debounceSeconds: Double {
        didSet { defaults.set(debounceSeconds, forKey: Key.debounceSeconds) }
    }
    @Published var autoDismissSeconds: Double {
        didSet { defaults.set(autoDismissSeconds, forKey: Key.autoDismissSeconds) }
    }
    @Published var logLevel: String {
        didSet { defaults.set(logLevel, forKey: Key.logLevel) }
    }
    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboardingCompleted) }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) }
    }

    private init() {
        self.enabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        self.daemonURL = defaults.string(forKey: Key.daemonURL) ?? "http://127.0.0.1:17823"
        let savedExcluded = defaults.array(forKey: Key.excludedApps) as? [String]
        self.excludedApps = Set(savedExcluded ?? Array(Self.defaultExcludedApps))
        self.debounceSeconds = defaults.object(forKey: Key.debounceSeconds) as? Double ?? 1.5
        self.autoDismissSeconds = defaults.object(forKey: Key.autoDismissSeconds) as? Double ?? 8.0
        self.logLevel = defaults.string(forKey: Key.logLevel) ?? "Basic"
        self.onboardingCompleted = defaults.object(forKey: Key.onboardingCompleted) as? Bool ?? false
        self.launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
    }
}
