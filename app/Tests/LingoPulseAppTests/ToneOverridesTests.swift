import Testing
import Foundation
@testable import LingoPulseApp

@Suite struct ToneOverridesTests {

    @Test @MainActor func getReturnsNilWhenUnset() {
        let defaults = UserDefaults(suiteName: "ToneOverridesTest-\(UUID())")!
        let overrides = ToneOverrides(defaults: defaults)
        #expect(overrides.tone(for: "Slack") == nil)
    }

    @Test @MainActor func setAndGet() {
        let defaults = UserDefaults(suiteName: "ToneOverridesTest-\(UUID())")!
        let overrides = ToneOverrides(defaults: defaults)
        overrides.setTone("Casual", for: "Slack")
        #expect(overrides.tone(for: "Slack") == "Casual")
    }

    @Test @MainActor func multipleAppsIndependent() {
        let defaults = UserDefaults(suiteName: "ToneOverridesTest-\(UUID())")!
        let overrides = ToneOverrides(defaults: defaults)
        overrides.setTone("Technical", for: "Xcode")
        overrides.setTone("Professional", for: "Mail")
        #expect(overrides.tone(for: "Xcode") == "Technical")
        #expect(overrides.tone(for: "Mail") == "Professional")
    }
}
