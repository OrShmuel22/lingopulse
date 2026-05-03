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
        static let excludedApps = "lp.excludedApps"
        static let debounceSeconds = "lp.debounceSeconds"
        static let autoDismissSeconds = "lp.autoDismissSeconds"
        static let logLevel = "lp.logLevel"
        static let onboardingCompleted = "lp.onboardingCompleted"
        static let launchAtLogin = "lp.launchAtLogin"
        static let liveModeEnabled = "lp.liveModeEnabled"
        static let liveModeExcludedApps = "lp.liveModeExcludedApps"
        static let triggerSingleKey = "lp.triggerSingleKey"
        static let triggerDoubleTapMod = "lp.triggerDoubleTapMod"
        static let shellBridgeEnabled = "lp.shellBridgeEnabled"
        static let fixerModel = "lp.fixerModel"
        static let fixerPromptOverride = "lp.fixerPromptOverride"
        static let toneOverridesJSON = "lp.toneOverridesJSON"
    }

    static let defaultExcludedApps: Set<String> = [
        "iTerm2", "Terminal", "Alacritty", "WezTerm", "Hyper", "Warp"
    ]

    static let defaultLiveModeExcludedApps: [String] = [
        "1Password", "1Password 7", "iTerm2", "Terminal", "Alacritty", "WezTerm", "Hyper", "Warp"
    ]

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
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
    @Published var liveModeEnabled: Bool {
        didSet { defaults.set(liveModeEnabled, forKey: Key.liveModeEnabled) }
    }
    @Published var liveModeExcludedApps: Set<String> {
        didSet { defaults.set(Array(liveModeExcludedApps), forKey: Key.liveModeExcludedApps) }
    }
    @Published var triggerSingleKey: String {
        didSet { defaults.set(triggerSingleKey, forKey: Key.triggerSingleKey) }
    }
    @Published var triggerDoubleTapMod: String {
        didSet { defaults.set(triggerDoubleTapMod, forKey: Key.triggerDoubleTapMod) }
    }
    @Published var shellBridgeEnabled: Bool {
        didSet { defaults.set(shellBridgeEnabled, forKey: Key.shellBridgeEnabled) }
    }
    // nil means "use AppConfig default"
    @Published var fixerModel: String? {
        didSet {
            if let v = fixerModel { defaults.set(v, forKey: Key.fixerModel) }
            else { defaults.removeObject(forKey: Key.fixerModel) }
        }
    }
    // nil means "use built-in fixerTemplate"
    @Published var fixerPromptOverride: String? {
        didSet {
            if let v = fixerPromptOverride { defaults.set(v, forKey: Key.fixerPromptOverride) }
            else { defaults.removeObject(forKey: Key.fixerPromptOverride) }
        }
    }
    // empty dict means "use built-in toneDescriptions"
    @Published var toneOverrides: [String: String] {
        didSet {
            if toneOverrides.isEmpty {
                defaults.removeObject(forKey: Key.toneOverridesJSON)
            } else if let data = try? JSONSerialization.data(withJSONObject: toneOverrides) {
                defaults.set(data, forKey: Key.toneOverridesJSON)
            }
        }
    }

    private init() {
        self.enabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        let savedExcluded = defaults.array(forKey: Key.excludedApps) as? [String]
        self.excludedApps = Set(savedExcluded ?? Array(Self.defaultExcludedApps))
        self.debounceSeconds = defaults.object(forKey: Key.debounceSeconds) as? Double ?? 1.5
        self.autoDismissSeconds = defaults.object(forKey: Key.autoDismissSeconds) as? Double ?? 8.0
        self.logLevel = defaults.string(forKey: Key.logLevel) ?? "Basic"
        self.onboardingCompleted = defaults.object(forKey: Key.onboardingCompleted) as? Bool ?? false
        self.launchAtLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
        self.liveModeEnabled = defaults.object(forKey: Key.liveModeEnabled) as? Bool ?? false
        let savedExcl = defaults.array(forKey: Key.liveModeExcludedApps) as? [String]
        self.liveModeExcludedApps = Set(savedExcl ?? Self.defaultLiveModeExcludedApps)
        self.triggerSingleKey = defaults.string(forKey: Key.triggerSingleKey) ?? "rightCommand"
        self.triggerDoubleTapMod = defaults.string(forKey: Key.triggerDoubleTapMod) ?? "shift"
        self.shellBridgeEnabled = defaults.object(forKey: Key.shellBridgeEnabled) as? Bool ?? false
        self.fixerModel = defaults.string(forKey: Key.fixerModel)
        self.fixerPromptOverride = defaults.string(forKey: Key.fixerPromptOverride)
        if let data = defaults.data(forKey: Key.toneOverridesJSON),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            self.toneOverrides = dict
        } else {
            self.toneOverrides = [:]
        }
    }
}
