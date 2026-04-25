import Testing
import Foundation
@testable import LingoPulseApp

@Suite struct EditTests {
    @Test func decodesValidEditPayload() throws {
        let json = #"{"type":"replace","from_text":"on","to_text":"for","from_span":[3,4],"to_span":[3,4],"category":"preposition","reason":"Wrong preposition"}"#
        let edit = try JSONDecoder().decode(Edit.self, from: Data(json.utf8))
        #expect(edit.from_text == "on")
        #expect(edit.to_text == "for")
        #expect(edit.category == "preposition")
    }

    @Test func categoryEnumMapping() throws {
        let json = #"{"type":"replace","from_text":"x","to_text":"y","from_span":[0,1],"to_span":[0,1],"category":"preposition","reason":""}"#
        let edit = try JSONDecoder().decode(Edit.self, from: Data(json.utf8))
        #expect(edit.categoryEnum == EditCategory.preposition)
    }

    @Test func unknownCategoryFallsBackToOther() throws {
        let json = #"{"type":"replace","from_text":"x","to_text":"y","from_span":[0,1],"to_span":[0,1],"category":"totally-unknown","reason":""}"#
        let edit = try JSONDecoder().decode(Edit.self, from: Data(json.utf8))
        #expect(edit.categoryEnum == EditCategory.other)
    }

    @Test func decodesConfidenceAndRisk() throws {
        let json = #"{"type":"replace","from_text":"on","to_text":"for","from_span":[0,1],"to_span":[0,1],"category":"preposition","reason":"","confidence":"high","risk":"safe"}"#
        let edit = try JSONDecoder().decode(Edit.self, from: Data(json.utf8))
        #expect(edit.confidenceEnum == .high)
        #expect(edit.riskEnum == .safe)
    }

    @Test func riskyEditDecodes() throws {
        let json = #"{"type":"replace","from_text":"x","to_text":"y","from_span":[0,1],"to_span":[0,1],"category":"grammar","reason":"","confidence":"low","risk":"risky"}"#
        let edit = try JSONDecoder().decode(Edit.self, from: Data(json.utf8))
        #expect(edit.confidenceEnum == .low)
        #expect(edit.riskEnum == .risky)
    }

    @Test func missingConfidenceRiskDefaultsToLowSafe() throws {
        // Backward compat: old payloads without these fields should decode with defaults
        let json = #"{"type":"replace","from_text":"x","to_text":"y","from_span":[0,1],"to_span":[0,1],"category":"typo","reason":""}"#
        let edit = try JSONDecoder().decode(Edit.self, from: Data(json.utf8))
        #expect(edit.confidenceEnum == .low)
        #expect(edit.riskEnum == .safe)
    }

    @Test func unknownConfidenceFallsBackToLow() throws {
        let json = #"{"type":"replace","from_text":"x","to_text":"y","from_span":[0,1],"to_span":[0,1],"category":"typo","reason":"","confidence":"ultra","risk":"safe"}"#
        let edit = try JSONDecoder().decode(Edit.self, from: Data(json.utf8))
        #expect(edit.confidenceEnum == .low)
    }
}
