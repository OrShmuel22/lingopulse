import Testing
import AppKit
@testable import LingoPulseApp

// GhostOverlayWindow.show() creates NSPanel objects; NSPanel requires an app
// event loop and a screen. In the headless swift test runner there is no
// NSApplication / main run loop, so orderFrontRegardless() is a no-op and the
// window is never displayed. The test below verifies construction and
// show/close round-trips don't crash.

@Suite @MainActor struct GhostOverlayWindowTests {

    @Test func showAndCloseSmokeNoCrash() {
        let overlay = GhostOverlayWindow()

        // Construct a minimal LiveSuggestion with a dummy element.
        // AXUIElementCreateSystemWide() returns a valid (if non-interactive)
        // AXUIElement that won't crash CaretLocator lookups.
        let dummyElement = AXUIElementCreateSystemWide()
        let suggestion = LiveSuggestion(
            element: dummyElement,
            original: "hello world",
            refined: "Hello, world.",
            anchorRect: CGRect(x: 100, y: 200, width: 1, height: 16)
        )

        // Must not crash
        overlay.show(suggestion: suggestion, onApply: {})
        overlay.close()

        // Second close is idempotent
        overlay.close()
    }
}
