import Testing
import Foundation
@testable import LingoPulseIMECore

@Suite struct IMEEnvelopeTests {
    struct SimplePayload: Decodable, Equatable {
        let value: Int
    }

    @Test func successEnvelopeDecodes() throws {
        let json = #"{"ok":true,"data":{"value":7}}"#
        let env = try JSONDecoder().decode(IMEEnvelope<SimplePayload>.self, from: Data(json.utf8))
        guard case .success(let p) = env else {
            Issue.record("expected success, got \(env)")
            return
        }
        #expect(p.value == 7)
    }

    @Test func failureEnvelopeDecodes() throws {
        let json = #"{"ok":false,"error":"daemon down"}"#
        let env = try JSONDecoder().decode(IMEEnvelope<SimplePayload>.self, from: Data(json.utf8))
        guard case .failure(let msg) = env else {
            Issue.record("expected failure, got \(env)")
            return
        }
        #expect(msg == "daemon down")
    }

    @Test func invalidEnvelopeThrows() {
        let json = #"{"ok":true}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(IMEEnvelope<SimplePayload>.self, from: Data(json.utf8))
        }
    }

    @Test func editMissingConfidenceRiskDefaultsToLowSafe() throws {
        let json = #"{"type":"replace","from_text":"x","to_text":"y","from_span":[0,1],"to_span":[0,1],"category":"typo","reason":""}"#
        let edit = try JSONDecoder().decode(IMEEdit.self, from: Data(json.utf8))
        #expect(edit.confidence == "low")
        #expect(edit.risk == "safe")
    }

    @Test func editWithConfidenceRiskDecodes() throws {
        let json = #"{"type":"replace","from_text":"a","to_text":"b","from_span":[0,1],"to_span":[0,1],"category":"grammar","reason":"","confidence":"high","risk":"risky"}"#
        let edit = try JSONDecoder().decode(IMEEdit.self, from: Data(json.utf8))
        #expect(edit.confidence == "high")
        #expect(edit.risk == "risky")
    }
}
