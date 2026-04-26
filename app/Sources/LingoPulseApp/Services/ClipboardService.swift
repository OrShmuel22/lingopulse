import AppKit

// CGEvent synthesis (copySelectionViaShortcut / pasteTextViaShortcut) is integration-only;
// unit tests are skipped — see ClipboardSnapshotTests for pasteboard-level coverage.

enum ClipboardService {
    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func pasteText(from pasteboard: NSPasteboard = .general) -> String {
        pasteboard.string(forType: .string) ?? ""
    }
}

/// Save current pasteboard string, restore via `restore()`.
/// Text-only — non-text items (images, files) are NOT preserved (matches Python behaviour).
/// Caller is responsible for calling `restore()` after paste-back is complete.
final class ClipboardSnapshot {
    private let saved: String
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.saved = ClipboardService.pasteText(from: pasteboard)
    }

    func restore() {
        ClipboardService.copy(saved, to: pasteboard)
    }
}
