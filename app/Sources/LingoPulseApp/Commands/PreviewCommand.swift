import AppKit

@MainActor
final class PreviewCommand {
    private let fixer: Fixer
    private let accessibility: AccessibilityServicing
    // Injected so tests can supply a no-op instead of UNUserNotificationCenter (unavailable in CLI).
    private let notify: (String, String) -> Void

    init(
        fixer: Fixer,
        accessibility: AccessibilityServicing,
        notify: @escaping (String, String) -> Void = { title, body in
            Notifications.show(title: title, body: body)
        }
    ) {
        self.fixer = fixer
        self.accessibility = accessibility
        self.notify = notify
    }

    func execute() async {
        let selection: String
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        if let sel = accessibility.readSelection() {
            selection = sel.text
        } else if let fb = await accessibility.pasteboardFallbackRead(), !fb.isEmpty {
            selection = fb
        } else {
            notify("LingoPulse", "No selection.")
            return
        }

        let result: FixerResult
        do {
            result = try await fixer.refine(selection: selection, app: app)
        } catch {
            Log.error("preview refine error: \(error)")
            notify("LingoPulse", "Preview failed: \(error)")
            return
        }

        await PreviewPanel().show(
            original: result.original,
            refined: result.refined,
            onAccept: { [weak self] in
                guard let self = self else { return }
                self.applyRefined(result.refined)
            },
            onReject: { [weak self] in
                guard let self = self else { return }
                Task { _ = try? await self.fixer.ring.popLatest() }
                Log.info("preview rejected — rolled back ring entry")
            }
        )
    }

    private func applyRefined(_ text: String) {
        if !accessibility.writeFocusedValue(text) {
            Task { @MainActor in
                let snap = ClipboardSnapshot()
                ClipboardService.copy(text)
                await SelectionService.pasteTextViaShortcut(text)
                try? await Task.sleep(for: .milliseconds(120))
                snap.restore()
            }
        }
    }
}
