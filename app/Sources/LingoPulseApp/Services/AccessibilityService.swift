import AppKit
import ApplicationServices

protocol AccessibilityServicing {
    var isTrusted: Bool { get }
    func readSelection() -> Selection?
    @discardableResult func writeFocusedValue(_ text: String) -> Bool
    func pasteboardFallbackRead() async -> String?
}

// Caller convention for pasteboardFallbackRead:
//   let snap = ClipboardSnapshot()
//   defer { snap.restore() }
//   let selected = await accessibility.pasteboardFallbackRead()
//   // ... refine, paste back ...
// The caller owns restore() because the refine flow keeps the clipboard busy for paste-back.

final class AccessibilityService: AccessibilityServicing {
    var isTrusted: Bool { AXIsProcessTrusted() }

    func readSelection() -> Selection? {
        guard let (text, app, element) = AXClient.readSelection() else { return nil }
        return Selection(text: text, appName: app, element: element)
    }

    @discardableResult func writeFocusedValue(_ text: String) -> Bool {
        AXClient.writeFocusedValue(text)
    }

    func pasteboardFallbackRead() async -> String? {
        let text = await SelectionService.copySelectionViaShortcut()
        return text.isEmpty ? nil : text
    }
}
