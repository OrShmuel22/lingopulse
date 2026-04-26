import AppKit
import ApplicationServices

@MainActor
final class AppCoordinator {
    let fixer: Fixer
    private let accessibility: AccessibilityServicing
    private var currentRefineTask: Task<Void, Never>?

    init(fixer: Fixer, accessibility: AccessibilityServicing) {
        self.fixer = fixer
        self.accessibility = accessibility
    }

    func refineFocusedSelection() {
        currentRefineTask?.cancel()
        currentRefineTask = Task { @MainActor in
            let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"

            let selectionText: String
            if let sel = accessibility.readSelection() {
                selectionText = sel.text
            } else if let fallback = await accessibility.pasteboardFallbackRead(), !fallback.isEmpty {
                selectionText = fallback
            } else {
                if !accessibility.isTrusted {
                    Notifications.show(title: "LingoPulse", body: "Accessibility permission revoked. Re-enable in System Settings → Privacy → Accessibility.")
                } else {
                    Notifications.show(title: "LingoPulse", body: "No selection. Select text first.")
                }
                return
            }

            if await fixer.alreadyRefined(selectionText) {
                Log.info("skip — selection matches recent refinement")
                return
            }

            do {
                let result = try await fixer.refine(selection: selectionText, app: appName)
                applyRefined(result.refined)
            } catch FixerError.emptySelection {
                Log.info("empty selection")
            } catch FixerError.ollama(.busy) {
                Log.info("ollama busy — try again in a moment")
            } catch FixerError.ollama(.timeout) {
                Notifications.show(title: "LingoPulse", body: "Refinement timed out. Model may be cold.")
            } catch {
                Log.error("refine error: \(error)")
                Notifications.show(title: "LingoPulse", body: "Refine failed: \(error)")
            }
        }
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

    func undoLast() {
        let cmd = UndoCommand(ring: fixer.ring, accessibility: accessibility)
        Task { @MainActor in await cmd.execute() }
    }
    func previewSelection() {
        let cmd = PreviewCommand(fixer: fixer, accessibility: accessibility)
        Task { @MainActor in await cmd.execute() }
    }
    func refineWithTone() {
        let cmd = ToneCommand(fixer: fixer, accessibility: accessibility)
        Task { @MainActor in await cmd.execute() }
    }
    func lookupWord() {
        let cmd = DictionaryCommand(ollama: fixer.ollama, config: fixer.config, accessibility: accessibility)
        Task { @MainActor in await cmd.execute() }
    }
    func captureStyleExample() {
        let store = StyleExamplesStore()
        let cmd = CaptureStyleCommand(store: store, accessibility: accessibility)
        Task { @MainActor in await cmd.execute() }
    }
}
