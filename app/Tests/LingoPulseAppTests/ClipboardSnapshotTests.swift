import Testing
import AppKit
@testable import LingoPulseApp

// Uses a named test pasteboard to avoid touching NSPasteboard.general in headless CI.
private func testPasteboard() -> NSPasteboard {
    let pb = NSPasteboard(name: .init("LingoPulseTest"))
    pb.clearContents()
    return pb
}

@Suite @MainActor struct ClipboardSnapshotTests {
    @Test func saveAndRestore() {
        let pb = testPasteboard()
        ClipboardService.copy("original", to: pb)

        let snap = ClipboardSnapshot(pasteboard: pb)
        ClipboardService.copy("mutated", to: pb)
        #expect(ClipboardService.pasteText(from: pb) == "mutated")

        snap.restore()
        #expect(ClipboardService.pasteText(from: pb) == "original")
    }

    @Test func emptyInitialClipboard() {
        let pb = testPasteboard()
        // pasteboard is cleared — pasteText returns ""
        let snap = ClipboardSnapshot(pasteboard: pb)
        ClipboardService.copy("something", to: pb)

        snap.restore()
        #expect(ClipboardService.pasteText(from: pb) == "")
    }
}
