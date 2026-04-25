import Foundation
import Combine
import Carbon.HIToolbox

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let enabled = "lp.enabled"
        static let hotkeyKeyCode = "lp.hotkey.keyCode"
        static let hotkeyModifiers = "lp.hotkey.modifiers"
        static let daemonURL = "lp.daemon.url"
        static let excludedApps = "lp.excludedApps"
        static let debounceSeconds = "lp.debounceSeconds"
        static let autoDismissSeconds = "lp.autoDismissSeconds"
        static let logLevel = "lp.logLevel"
    }

    static let defaultExcludedApps: Set<String> = [
        "iTerm2", "Terminal", "Alacritty", "WezTerm", "Hyper", "Warp"
    ]

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
    }
    @Published var hotkeyKeyCode: Int {
        didSet { defaults.set(hotkeyKeyCode, forKey: Key.hotkeyKeyCode) }
    }
    @Published var hotkeyModifiers: UInt32 {
        didSet { defaults.set(Int(hotkeyModifiers), forKey: Key.hotkeyModifiers) }
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

    private init() {
        self.enabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        self.hotkeyKeyCode = defaults.object(forKey: Key.hotkeyKeyCode) as? Int ?? Int(kVK_ANSI_G)
        self.hotkeyModifiers = UInt32(defaults.object(forKey: Key.hotkeyModifiers) as? Int ?? Int(cmdKey | optionKey))
        self.daemonURL = defaults.string(forKey: Key.daemonURL) ?? "http://127.0.0.1:17823"
        let savedExcluded = defaults.array(forKey: Key.excludedApps) as? [String]
        self.excludedApps = Set(savedExcluded ?? Array(Self.defaultExcludedApps))
        self.debounceSeconds = defaults.object(forKey: Key.debounceSeconds) as? Double ?? 1.5
        self.autoDismissSeconds = defaults.object(forKey: Key.autoDismissSeconds) as? Double ?? 8.0
        self.logLevel = defaults.string(forKey: Key.logLevel) ?? "Basic"
    }
}
