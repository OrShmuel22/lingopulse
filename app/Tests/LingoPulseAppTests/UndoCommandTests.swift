import Testing
import Foundation
@testable import LingoPulseApp

// MARK: - Stub

private final class StubAccessibility: AccessibilityServicing {
    var isTrusted: Bool = true
    var selectionText: String?
    var writeSucceeds: Bool = true
    private(set) var writeCallCount = 0

    func readSelection() -> Selection? {
        guard let t = selectionText else { return nil }
        return Selection(text: t, appName: "TestApp", element: nil)
    }

    @discardableResult func writeFocusedValue(_ text: String) -> Bool {
        writeCallCount += 1
        return writeSucceeds
    }

    func pasteboardFallbackRead() async -> String? { nil }
}

// MARK: - Helpers

private func tempRingURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("undo-test-ring-\(UUID().uuidString).json")
}

// No-op notify avoids UNUserNotificationCenter (unavailable in CLI test runner).
private let noopNotify: (String, String) -> Void = { _, _ in }

// MARK: - Tests

@Suite struct UndoCommandTests {

    @Test @MainActor func undoWithMatchingSelection() async throws {
        let ring = RingBuffer(fileURL: tempRingURL(), size: 5)
        try await ring.append(["original": "hello world", "refined": "Hello, world.", "app": "TestApp"])

        let stub = StubAccessibility()
        stub.selectionText = "Hello, world."
        stub.writeSucceeds = true

        let cmd = UndoCommand(ring: ring, accessibility: stub, notify: noopNotify)
        await cmd.execute()

        let remaining = try await ring.listAll()
        #expect(remaining.isEmpty)
        #expect(stub.writeCallCount == 1)
    }

    @Test @MainActor func undoWithEmptyRing() async throws {
        let ring = RingBuffer(fileURL: tempRingURL(), size: 5)

        let stub = StubAccessibility()
        stub.selectionText = "anything"

        let cmd = UndoCommand(ring: ring, accessibility: stub, notify: noopNotify)
        await cmd.execute()

        let remaining = try await ring.listAll()
        #expect(remaining.isEmpty)
    }

    @Test @MainActor func undoWithNonMatchingSelection() async throws {
        let ring = RingBuffer(fileURL: tempRingURL(), size: 5)
        try await ring.append(["original": "hello world", "refined": "Hello, world.", "app": "TestApp"])

        let stub = StubAccessibility()
        stub.selectionText = "Something completely different"

        let cmd = UndoCommand(ring: ring, accessibility: stub, notify: noopNotify)
        await cmd.execute()

        let remaining = try await ring.listAll()
        #expect(remaining.count == 1)
        #expect(stub.writeCallCount == 0)
    }
}
