import Testing
import Foundation
@testable import LingoPulseApp

@Suite struct ConfidenceRiskTests {
    // Test Confidence enum raw values decode correctly
    @Test func confidenceHighRawValue() {
        #expect(Confidence(rawValue: "high") == .high)
    }

    @Test func confidenceMediumRawValue() {
        #expect(Confidence(rawValue: "medium") == .medium)
    }

    @Test func riskSafeRawValue() {
        #expect(Risk(rawValue: "safe") == .safe)
    }

    @Test func riskRiskyRawValue() {
        #expect(Risk(rawValue: "risky") == .risky)
    }
}
