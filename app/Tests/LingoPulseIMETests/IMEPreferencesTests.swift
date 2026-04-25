import Testing
import Foundation
@testable import LingoPulseIMECore

// MARK: - IMEPreferences read-path tests
//
// These tests exercise IMEPreferences using a real UserDefaults instance backed
// by a unique in-memory suite so they are isolated and require no signed App
// Group container.

@Suite struct IMEPreferencesTests {

    // Helper: create an isolated UserDefaults suite and return both the suite
    // and a pre-configured IMEPreferences that reads from it.
    private func makeSuite(name: String = "test.\(UUID().uuidString)") -> (UserDefaults, IMEPreferences) {
        let ud = UserDefaults(suiteName: name)!
        // Remove any residual keys from a previous run.
        ud.removePersistentDomain(forName: name)
        let prefs = IMEPreferences(defaults: ud)
        return (ud, prefs)
    }

    // MARK: - Default excluded apps

    @Test func defaultExcludedAppsContainsTerminals() {
        let defaults = IMEPreferences.defaultExcludedApps
        #expect(defaults.contains("iTerm2"))
        #expect(defaults.contains("Terminal"))
        #expect(defaults.contains("Alacritty"))
        #expect(defaults.contains("WezTerm"))
        #expect(defaults.contains("Hyper"))
        #expect(defaults.contains("Warp"))
    }

    @Test func excludedAppsReturnsDefaultsWhenKeyAbsent() {
        let (_, prefs) = makeSuite()
        // No key written → should return the built-in defaults.
        let excluded = prefs.excludedApps
        for app in IMEPreferences.defaultExcludedApps {
            #expect(excluded.contains(app),
                    "Expected default excluded app '\(app)' to be present")
        }
    }

    // MARK: - Reads written values

    @Test func excludedAppsReflectsWrittenArray() {
        let (ud, prefs) = makeSuite()
        ud.set(["Slack", "Discord"], forKey: "lp.excludedApps")
        let excluded = prefs.excludedApps
        #expect(excluded == ["Slack", "Discord"])
    }

    @Test func excludedAppsEmptyArrayIsRespected() {
        let (ud, prefs) = makeSuite()
        ud.set([] as [String], forKey: "lp.excludedApps")
        let excluded = prefs.excludedApps
        #expect(excluded.isEmpty)
    }

    @Test func excludedAppsReflectsUpdatedValue() {
        let (ud, prefs) = makeSuite()
        ud.set(["Terminal"], forKey: "lp.excludedApps")
        #expect(prefs.excludedApps == ["Terminal"])
        ud.set(["Warp", "Alacritty"], forKey: "lp.excludedApps")
        #expect(prefs.excludedApps == ["Warp", "Alacritty"])
    }

    @Test func excludedAppsContainsCheckPositive() {
        let (ud, prefs) = makeSuite()
        ud.set(["VSCode", "Xcode"], forKey: "lp.excludedApps")
        #expect(prefs.excludedApps.contains("VSCode"))
        #expect(prefs.excludedApps.contains("Xcode"))
    }

    @Test func excludedAppsContainsCheckNegative() {
        let (ud, prefs) = makeSuite()
        ud.set(["Terminal"], forKey: "lp.excludedApps")
        #expect(!prefs.excludedApps.contains("Slack"))
    }

    // MARK: - App Group ID constant

    @Test func appGroupIDMatchesMainApp() {
        // The IMEPreferences.appGroupID must stay in sync with Preferences.appGroupID.
        #expect(IMEPreferences.appGroupID == "group.com.lingopulse.shared")
    }
}
