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
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        guard let sel = await accessibility.readOrFallback() else {
            notify("LingoPulse", "No selection.")
            return
        }
        let selection = sel.text
        // Element nil ⇒ AX read failed and we read via clipboard (⌘C synth).
        // Almost always implies AX write will fail too — flag the panel so it
        // pre-copies the refined text and shows the keyboard-only paste flow.
        let axWriteAvailable = sel.element != nil
        let capturedElement = sel.element

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
            axWriteAvailable: axWriteAvailable,
            onAccept: { [weak self] in
                guard let self = self else { return }
                // Use the element captured at refine time. Fresh focused-element
                // lookup races with focus restoration after the panel dismisses
                // (especially in browser URL bars).
                self.accessibility.applyTextWithFallback(result.refined, to: capturedElement)
            },
            onReject: { [weak self] in
                guard let self = self else { return }
                Task { _ = try? await self.fixer.ring.popLatest() }
                Log.info("preview rejected — rolled back ring entry")
            }
        )
    }
}
