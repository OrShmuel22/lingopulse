import Testing
import Foundation
@testable import LingoPulseIMECore

// MARK: - ApplyEdits decoding tests

@Suite struct ApplyEditsDecodingTests {

    // Helper: build a minimal IMEEdit JSON fragment.
    private func editJSON(from: String = "x", to: String = "y") -> String {
        """
        {"type":"replace","from_text":"\(from)","to_text":"\(to)",\
        "from_span":[0,1],"to_span":[0,1],\
        "category":"typo","reason":"","confidence":"high","risk":"safe"}
        """
    }

    @Test func applyEditsResponseDecodesRefined() throws {
        let json = """
        {"ok":true,"data":{"original":"helo world","refined":"hello world","edits":[]}}
        """
        let env = try JSONDecoder().decode(
            IMEEnvelope<IMEApplyEditsResponse>.self, from: Data(json.utf8))
        guard case .success(let r) = env else {
            Issue.record("expected success"); return
        }
        #expect(r.original == "helo world")
        #expect(r.refined == "hello world")
        #expect(r.edits.isEmpty)
    }

    @Test func applyEditsResponseDecodesResidualEdits() throws {
        let e = editJSON(from: "a", to: "b")
        let json = """
        {"ok":true,"data":{"original":"a c","refined":"b c","edits":[\(e)]}}
        """
        let env = try JSONDecoder().decode(
            IMEEnvelope<IMEApplyEditsResponse>.self, from: Data(json.utf8))
        guard case .success(let r) = env else {
            Issue.record("expected success"); return
        }
        #expect(r.edits.count == 1)
        #expect(r.edits[0].from_text == "a")
        #expect(r.edits[0].to_text == "b")
    }

    @Test func applyEditsResponseFailureEnvelopeDecodes() throws {
        let json = #"{"ok":false,"error":"edit index out of range"}"#
        let env = try JSONDecoder().decode(
            IMEEnvelope<IMEApplyEditsResponse>.self, from: Data(json.utf8))
        guard case .failure(let msg) = env else {
            Issue.record("expected failure"); return
        }
        #expect(msg == "edit index out of range")
    }

    @Test func applyEditsResponseWithMissingConfidenceDefaultsToLow() throws {
        let editNoConf = """
        {"type":"replace","from_text":"foo","to_text":"bar",\
        "from_span":[0,3],"to_span":[0,3],\
        "category":"style","reason":""}
        """
        let json = """
        {"ok":true,"data":{"original":"foo baz","refined":"bar baz","edits":[\(editNoConf)]}}
        """
        let env = try JSONDecoder().decode(
            IMEEnvelope<IMEApplyEditsResponse>.self, from: Data(json.utf8))
        guard case .success(let r) = env else {
            Issue.record("expected success"); return
        }
        #expect(r.edits[0].confidence == "low")
        #expect(r.edits[0].risk == "safe")
    }
}

// MARK: - SuggestionWindow cycling tests
//
// SuggestionWindow is an AppKit class that creates an NSPanel, so it cannot be
// instantiated in a plain Swift test target without a running NSApplication.
// We test the pure cycling logic by extracting the state machine into a small
// helper type that mirrors SuggestionWindow's index arithmetic.

/// Pure-Swift mirror of SuggestionWindow's cycling state — testable without AppKit.
struct CycleState {
    private(set) var selectedIndex: Int = 0
    let count: Int

    mutating func cycleDown() {
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + 1) % count
    }

    mutating func cycleUp() {
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + count - 1) % count
    }
}

@Suite struct SuggestionCyclingTests {

    @Test func initialIndexIsZero() {
        let s = CycleState(count: 3)
        #expect(s.selectedIndex == 0)
    }

    @Test func cycleDownAdvancesIndex() {
        var s = CycleState(count: 3)
        s.cycleDown()
        #expect(s.selectedIndex == 1)
        s.cycleDown()
        #expect(s.selectedIndex == 2)
    }

    @Test func cycleDownWrapsFromLastToFirst() {
        var s = CycleState(count: 3)
        s.cycleDown() // 1
        s.cycleDown() // 2
        s.cycleDown() // wraps to 0
        #expect(s.selectedIndex == 0)
    }

    @Test func cycleUpFromZeroWrapsToLast() {
        var s = CycleState(count: 3)
        s.cycleUp()
        #expect(s.selectedIndex == 2)
    }

    @Test func cycleUpDecreasesIndex() {
        var s = CycleState(count: 3)
        s.cycleDown() // 1
        s.cycleDown() // 2
        s.cycleUp()   // 1
        #expect(s.selectedIndex == 1)
    }

    @Test func cycleUpWrapsFromFirstToLast() {
        var s = CycleState(count: 4)
        s.cycleUp() // 3
        s.cycleUp() // 2
        s.cycleUp() // 1
        s.cycleUp() // 0
        #expect(s.selectedIndex == 0)
    }

    @Test func singleEditCycleDownStaysAtZero() {
        var s = CycleState(count: 1)
        s.cycleDown()
        #expect(s.selectedIndex == 0)
    }

    @Test func singleEditCycleUpStaysAtZero() {
        var s = CycleState(count: 1)
        s.cycleUp()
        #expect(s.selectedIndex == 0)
    }

    @Test func zeroCountCycleIsNoop() {
        var s = CycleState(count: 0)
        s.cycleDown()
        #expect(s.selectedIndex == 0)
        s.cycleUp()
        #expect(s.selectedIndex == 0)
    }

    @Test func fullRoundTripDownThenUpReturnsToStart() {
        let n = 5
        var s = CycleState(count: n)
        for _ in 0..<n { s.cycleDown() }
        #expect(s.selectedIndex == 0)
        for _ in 0..<n { s.cycleUp() }
        #expect(s.selectedIndex == 0)
    }
}
