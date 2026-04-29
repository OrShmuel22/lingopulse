import AppKit
import ApplicationServices

protocol AccessibilityServicing {
    var isTrusted: Bool { get }
    func readSelection() -> Selection?
    @discardableResult func writeFocusedValue(_ text: String) -> Bool
    func pasteboardFallbackRead() async -> String?
    func readOrFallback() async -> Selection?
}

extension AccessibilityServicing {
    // Try to write `text` to the focused field via AX. On failure, fall back to clipboard paste
    // with snapshot/restore. Used by all "apply refined text" flows so the recovery sequence
    // exists in one place.
    //
    // When `element` is provided (captured at selection-read time), the write
    // targets it directly — this is the reliable path for URL bars and other
    // fields that lose focus while a panel is on screen, because the lookup
    // "current frontmost app's focused element" can race with focus
    // restoration. Pass nil only when no element was captured (clipboard
    // fallback read).
    @MainActor
    func applyTextWithFallback(_ text: String, to element: AXUIElement? = nil, restoreDelayMs: Int = 120) {
        if let element, AXClient.writeValue(to: element, text: text) { return }
        if writeFocusedValue(text) { return }
        if let element {
            // AX write rejected (some Chromium / Electron URL bars). Force
            // focus to the captured element, then synthesize ⌘V — pasted text
            // replaces whatever's currently selected in that field. Most URL
            // bars auto-select on focus so this overwrites the URL.
            AXClient.setSystemwideFocus(element)
        }
        let snap = ClipboardSnapshot()
        ClipboardService.copy(text)
        Task { @MainActor in
            // Brief delay so the focus change settles before the synthesized
            // ⌘V hits the HID event tap.
            try? await Task.sleep(for: .milliseconds(40))
            await SelectionService.pasteTextViaShortcut(text)
            try? await Task.sleep(for: .milliseconds(restoreDelayMs))
            snap.restore()
        }
    }
}

// Caller convention for pasteboardFallbackRead:
//   let snap = ClipboardSnapshot()
//   defer { snap.restore() }
//   let selected = await accessibility.pasteboardFallbackRead()
//   // ... refine, paste back ...
// The caller owns restore() because the refine flow keeps the clipboard busy for paste-back.

extension AccessibilityServicing {
    // Default implementation collapses the AX-then-clipboard pattern that every command repeats.
    // Returns nil only when both reads fail (or the clipboard text is empty) — callers handle the
    // "no selection" notification themselves to keep wording per-command.
    func readOrFallback() async -> Selection? {
        if let sel = readSelection() { return sel }
        guard let fb = await pasteboardFallbackRead(), !fb.isEmpty else { return nil }
        let appName = await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        }
        return Selection(text: fb, appName: appName, element: nil)
    }
}

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
