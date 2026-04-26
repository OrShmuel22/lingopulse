import Testing
import Foundation
@testable import LingoPulseApp

// Fixer is a concrete @MainActor final class with no protocol seam, so tests that require a
// fake refine() result are skipped — mocking would require either subclassing (blocked by final)
// or introducing a new protocol (out of scope). Instead we cover the paths that don't need a
// live LLM: empty selection → Notifications fires, no refine call.

// MARK: - Stubs

private final class StubAccessibility: AccessibilityServicing {
    var isTrusted: Bool = true
    var selectionText: String?
    var fallbackText: String?
    private(set) var writeCallCount = 0

    func readSelection() -> Selection? {
        guard let t = selectionText else { return nil }
        return Selection(text: t, appName: "TestApp", element: nil)
    }

    @discardableResult func writeFocusedValue(_ text: String) -> Bool {
        writeCallCount += 1
        return true
    }

    func pasteboardFallbackRead() async -> String? { fallbackText }
}

@MainActor
private func makeFixer() -> Fixer {
    let session = URLSession(configuration: .ephemeral)
    let ollama = OllamaService(session: session)
    let config = AppConfig(configURL: URL(fileURLWithPath: "/dev/null/nonexistent"))
    let ring = RingBuffer(
        fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("preview-ring-\(UUID().uuidString).json"),
        size: 5
    )
    let history = HistoryStore(
        fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("preview-hist-\(UUID().uuidString).jsonl")
    )
    return Fixer(ollama: ollama, config: config, history: history, ring: ring)
}

// MARK: - Tests

@Suite struct PreviewCommandTests {

    // Empty selection: both readSelection() and pasteboardFallbackRead() return nothing →
    // execute() must return early (Notifications fires). Assert no write or ring side-effects.
    @Test @MainActor func emptySelectionReturnsEarly() async throws {
        let stub = StubAccessibility()
        stub.selectionText = nil
        stub.fallbackText = nil

        let fixer = makeFixer()
        let cmd = PreviewCommand(fixer: fixer, accessibility: stub, notify: { _, _ in })
        await cmd.execute()   // must not hang or crash

        let ringEntries = try await fixer.ring.listAll()
        #expect(ringEntries.isEmpty)
        #expect(stub.writeCallCount == 0)
    }

    // Reject path: after a refine entry lands in the ring, calling popLatest() removes it.
    // This validates the rollback mechanic used by PreviewCommand.onReject without needing
    // to drive the full NSPanel UI.
    @Test @MainActor func rollbackRemovesLatestRingEntry() async throws {
        let ring = RingBuffer(
            fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("preview-rollback-\(UUID().uuidString).json"),
            size: 5
        )
        try await ring.append(["original": "hi", "refined": "Hello.", "app": "TestApp"])

        let before = try await ring.listAll()
        #expect(before.count == 1)

        _ = try await ring.popLatest()

        let after = try await ring.listAll()
        #expect(after.isEmpty)
    }
}
