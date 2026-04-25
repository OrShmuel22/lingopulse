import Testing
import Foundation
@testable import LingoPulseApp

// Helper to build an Edit with explicit confidence/risk strings
private func makeEdit(from fromText: String, to toText: String, risk: String, confidence: String = "high") -> Edit {
    let json = """
    {"type":"replace","from_text":"\(fromText)","to_text":"\(toText)","from_span":[0,1],"to_span":[0,1],"category":"grammar","reason":"","confidence":"\(confidence)","risk":"\(risk)"}
    """
    return try! JSONDecoder().decode(Edit.self, from: Data(json.utf8))
}

@Suite struct SafeIndicesTests {
    @Test @MainActor func allSafeEditsReturnAllIndices() {
        let edits = [
            makeEdit(from: "on", to: "for", risk: "safe"),
            makeEdit(from: "informations", to: "information", risk: "safe"),
        ]
        let result = RefineResult(original: "responsible on informations", refined: "responsible for information", edits: edits)
        let state = ReviewPanelState(result: result)
        #expect(state.safeIndices == [0, 1])
    }

    @Test @MainActor func riskyEditsExcludedFromSafeIndices() {
        let edits = [
            makeEdit(from: "on", to: "for", risk: "safe"),
            makeEdit(from: "im blocked", to: "I've been blocked", risk: "risky"),
        ]
        let result = RefineResult(original: "im blocked on PR", refined: "I've been blocked for PR", edits: edits)
        let state = ReviewPanelState(result: result)
        #expect(state.safeIndices == [0])
    }

    @Test @MainActor func allRiskyEditsReturnEmptySafeIndices() {
        let edits = [
            makeEdit(from: "im blocked", to: "I've been blocked", risk: "risky"),
            makeEdit(from: "fix this", to: "I fixed this", risk: "risky"),
        ]
        let result = RefineResult(original: "im blocked fix this", refined: "I've been blocked I fixed this", edits: edits)
        let state = ReviewPanelState(result: result)
        #expect(state.safeIndices.isEmpty)
    }
}
