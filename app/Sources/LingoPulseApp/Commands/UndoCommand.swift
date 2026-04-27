import AppKit

@MainActor
final class UndoCommand {
    private let ring: RingBuffer
    private let accessibility: AccessibilityServicing
    // Injected so tests can supply a no-op instead of UNUserNotificationCenter (unavailable in CLI).
    private let notify: (String, String) -> Void

    init(
        ring: RingBuffer,
        accessibility: AccessibilityServicing,
        notify: @escaping (String, String) -> Void = { title, body in
            Notifications.show(title: title, body: body)
        }
    ) {
        self.ring = ring
        self.accessibility = accessibility
        self.notify = notify
    }

    func execute() async {
        let currentSelection = await accessibility.readOrFallback()?.text

        guard let entries = try? await ring.listAll(), !entries.isEmpty else {
            notify("LingoPulse", "Nothing to undo.")
            return
        }
        let latest = entries[0]
        let refined = latest["refined"] as? String ?? ""
        let original = latest["original"] as? String ?? ""

        if let cur = currentSelection, cur == refined, !original.isEmpty {
            if !accessibility.writeFocusedValue(original) {
                let snap = ClipboardSnapshot()
                ClipboardService.copy(original)
                await SelectionService.pasteTextViaShortcut(original)
                try? await Task.sleep(for: .milliseconds(120))
                snap.restore()
            }
            _ = try? await ring.popLatest()
            notify("LingoPulse", "Undone.")
            return
        }

        await UndoFallbackPanel().show(entries: entries) { [weak self] selected in
            guard let self = self else { return }
            Task { @MainActor in
                let original = selected["original"] as? String ?? ""
                let snap = ClipboardSnapshot()
                ClipboardService.copy(original)
                await SelectionService.pasteTextViaShortcut(original)
                try? await Task.sleep(for: .milliseconds(120))
                snap.restore()
                _ = try? await self.ring.popLatest()
            }
        }
    }
}
