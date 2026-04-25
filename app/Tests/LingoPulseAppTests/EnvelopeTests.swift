import Testing
import Foundation
@testable import LingoPulseApp

@Suite struct EnvelopeTests {
    struct Payload: Decodable, Equatable {
        let value: Int
    }

    @Test func successEnvelope() throws {
        let json = #"{"ok":true,"data":{"value":42}}"#
        let env = try JSONDecoder().decode(Envelope<Payload>.self, from: Data(json.utf8))
        guard case .success(let p) = env else {
            Issue.record("expected success, got \(env)")
            return
        }
        #expect(p.value == 42)
    }

    @Test func failureEnvelope() throws {
        let json = #"{"ok":false,"error":"oops"}"#
        let env = try JSONDecoder().decode(Envelope<Payload>.self, from: Data(json.utf8))
        guard case .failure(let msg) = env else {
            Issue.record("expected failure, got \(env)")
            return
        }
        #expect(msg == "oops")
    }

    @Test func invalidEnvelopeThrows() {
        let json = #"{"ok":true}"#  // ok=true but no data
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Envelope<Payload>.self, from: Data(json.utf8))
        }
    }

    @Test func falseOKWithoutErrorThrows() {
        let json = #"{"ok":false}"#  // ok=false but no error
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Envelope<Payload>.self, from: Data(json.utf8))
        }
    }
}
