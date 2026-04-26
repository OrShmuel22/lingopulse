import AppKit
import CoreGraphics

// CGEvent key synthesis cannot be meaningfully unit-tested without a real HID session;
// copySelectionViaShortcut and pasteTextViaShortcut are integration-only.

private let kVK_ANSI_C: CGKeyCode = 0x08
private let kVK_ANSI_V: CGKeyCode = 0x09

private var _frontmostCache: (timestamp: Double, name: String)? = nil
private let _cacheTTL: Double = 0.1

enum SelectionService {
    static func frontmostAppName() -> String? {
        let now = CACurrentMediaTime()
        if let cache = _frontmostCache, (now - cache.timestamp) < _cacheTTL {
            return cache.name
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              let name = app.localizedName else { return nil }
        _frontmostCache = (now, name)
        return name
    }

    static func copySelectionViaShortcut() async -> String {
        sendCommandKey(kVK_ANSI_C)
        try? await Task.sleep(for: .milliseconds(50))
        return ClipboardService.pasteText()
    }

    static func pasteTextViaShortcut(_ text: String) async {
        ClipboardService.copy(text)
        sendCommandKey(kVK_ANSI_V)
    }
}

private func sendCommandKey(_ keyCode: CGKeyCode) {
    let src = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
    let up   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
    down?.flags = .maskCommand
    up?.flags   = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}
