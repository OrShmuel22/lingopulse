import Foundation

/// Read-only view of the shared LingoPulse preferences for use inside the IME bundle.
///
/// The main app writes preferences to the App Group suite
/// `group.com.lingopulse.shared` via `Preferences`.  This struct reads the
/// same suite so the IME bundle can consult user preferences (e.g. the
/// excluded-app list) without depending on the main app target.
///
/// Falls back to `UserDefaults.standard` when the group container is not
/// accessible (e.g. unit tests running without a signed App Group).
public struct IMEPreferences {

    /// App Group identifier shared between the main app and the IME bundle.
    public static let appGroupID = "group.com.lingopulse.shared"

    private static let excludedAppsKey = "lp.excludedApps"

    private let defaults: UserDefaults

    /// Creates an instance backed by the shared App Group suite.
    public init() {
        self.defaults = UserDefaults(suiteName: Self.appGroupID) ?? .standard
    }

    /// Initialiser used in tests: pass a pre-configured `UserDefaults` instance
    /// so no real group container is required.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The set of application names (localised) for which the IME should not
    /// trigger suggestions.  Mirrors `Preferences.excludedApps` in the main app.
    public var excludedApps: Set<String> {
        let stored = defaults.array(forKey: Self.excludedAppsKey) as? [String]
        return Set(stored ?? Array(Self.defaultExcludedApps))
    }

    /// The default set of excluded apps, matching the main app's default.
    public static let defaultExcludedApps: Set<String> = [
        "iTerm2", "Terminal", "Alacritty", "WezTerm", "Hyper", "Warp"
    ]
}
