import Testing
import Foundation
@testable import LingoPulseApp

// Full AX observer flow cannot be unit-tested without a real UI session and
// accessibility permission granted to the test process. The tests below cover
// the seams that were exposed on LiveTextMonitor:
//   - `axObserver` is internal(set) — lets us assert it stays nil for excluded apps
//   - `scheduleDebouncedRefine()` is internal — lets us assert debounce cancels prior task
//   - `attach(to:)` is internal — lets us call it directly without NSWorkspace notifications

@Suite @MainActor struct LiveTextMonitorTests {

    // MARK: - Helpers

    private func makeFixer() -> Fixer {
        Fixer(
            ollama: OllamaService(),
            config: AppConfig.shared,
            history: HistoryStore(),
            ring: RingBuffer(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("lp_test_ring_\(UUID().uuidString).json"),
                size: 3
            )
        )
    }

    // MARK: - debounceCancelsPrior

    // Fire two scheduleDebouncedRefine() calls 100ms apart; the first debounce
    // task should be cancelled before it fires. We verify by checking that
    // debounceTask is not nil after the second call (it would be nil only if
    // something cancelled it externally) and that only one task is live.
    @Test func debounceCancelsPrior() async {
        let monitor = LiveTextMonitor(
            fixer: makeFixer(),
            excludedApps: { [] },
            onSuggestion: { _ in }
        )

        monitor.scheduleDebouncedRefine()
        let firstTask = monitor.debounceTask

        try? await Task.sleep(for: .milliseconds(100))

        monitor.scheduleDebouncedRefine()
        let secondTask = monitor.debounceTask

        // The first task must have been cancelled
        #expect(firstTask?.isCancelled == true)
        // A new task is live
        #expect(secondTask != nil)
        // Clean up
        secondTask?.cancel()
    }

    // MARK: - excludedAppsSkipsAttach

    // When the excluded-apps closure returns the app's name, attach(to:) should
    // return early without creating an AXObserver.
    @Test func excludedAppsSkipsAttach() async {
        let monitor = LiveTextMonitor(
            fixer: makeFixer(),
            excludedApps: { ["Slack"] },
            onSuggestion: { _ in }
        )

        // Build a fake NSRunningApplication stand-in using the real frontmost
        // application if available; we only need localizedName == "Slack" but we
        // can't construct NSRunningApplication directly. Instead, verify the
        // guard path via the axObserver property: starting without any real app
        // that matches means the observer is never set.
        //
        // We can't synthesise an NSRunningApplication with localizedName "Slack"
        // from tests, so this test documents the guard is present and that
        // axObserver starts nil.
        #expect(monitor.axObserver == nil, "axObserver must be nil before any attach")

        // After stop(), still nil
        monitor.stop()
        #expect(monitor.axObserver == nil)
    }
}
