import Testing
import Foundation
@testable import LingoPulseApp

// Helper to build an Edit
private func makeEditA(from fromText: String, to toText: String) -> Edit {
    let json = """
    {"type":"replace","from_text":"\(fromText)","to_text":"\(toText)","from_span":[0,1],"to_span":[0,1],"category":"grammar","reason":"","confidence":"high","risk":"safe"}
    """
    return try! JSONDecoder().decode(Edit.self, from: Data(json.utf8))
}

@Suite struct AcceptedIndicesTests {
    @Test @MainActor func acceptedIndicesReflectsToggledEdits() {
        let edits = [
            makeEditA(from: "on", to: "for"),
            makeEditA(from: "informations", to: "information"),
            makeEditA(from: "feedbacks", to: "feedback"),
        ]
        let result = RefineResult(original: "a", refined: "b", edits: edits)
        let state = ReviewPanelState(result: result)

        // Initially nothing is accepted
        #expect(state.acceptedIndices.isEmpty)

        // Accept the first and third edits
        state.perEditAccepted[0] = true
        state.perEditAccepted[2] = true

        #expect(state.acceptedIndices == [0, 2])
    }

    @Test @MainActor func togglingOffRemovesFromAcceptedIndices() {
        let edits = [
            makeEditA(from: "on", to: "for"),
            makeEditA(from: "informations", to: "information"),
        ]
        let result = RefineResult(original: "a", refined: "b", edits: edits)
        let state = ReviewPanelState(result: result)

        state.perEditAccepted[0] = true
        state.perEditAccepted[1] = true
        #expect(state.acceptedIndices == [0, 1])

        // Toggle second edit off
        state.perEditAccepted[1] = false
        #expect(state.acceptedIndices == [0])
    }
}
