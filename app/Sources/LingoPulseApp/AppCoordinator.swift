import AppKit
import ApplicationServices

@MainActor
final class AppCoordinator {
    let fixer: Fixer
    private let accessibility: AccessibilityServicing
    private var currentRefineTask: Task<Void, Never>?
    private(set) var isRefining: Bool = false {
        didSet { if oldValue != isRefining { onRefiningChanged?(isRefining) } }
    }
    var onRefiningChanged: ((Bool) -> Void)?

    init(fixer: Fixer, accessibility: AccessibilityServicing) {
        self.fixer = fixer
        self.accessibility = accessibility
    }

    func refineFocusedSelection() {
        if isRefining {
            NSSound.beep()
            Log.info("refine ignored — already in flight")
            return
        }
        currentRefineTask?.cancel()
        isRefining = true
        currentRefineTask = Task { @MainActor in
            defer { isRefining = false }
            let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"

            guard let sel = await accessibility.readOrFallback() else {
                if !accessibility.isTrusted {
                    Alerts.modal(
                        key: "ax-revoked",
                        title: "Accessibility Permission Required",
                        body: "LingoPulse can't read selected text without Accessibility access. Re-enable it in System Settings → Privacy & Security → Accessibility.",
                        primaryButton: "Open System Settings",
                        secondaryButton: "Later",
                        onPrimary: { Alerts.openAccessibilitySettings() }
                    )
                } else {
                    Alerts.toast("No text selected — select text and try again.")
                }
                return
            }
            let selectionText = sel.text

            if await fixer.alreadyRefined(selectionText) {
                Log.info("skip — selection matches recent refinement")
                return
            }

            do {
                let result = try await fixer.refine(selection: selectionText, app: appName)
                if sel.element == nil {
                    // Source field doesn't expose AX writes (terminals, Claude
                    // Code, Cursor's terminal pane). Show Preview with auto-copy
                    // instead of synthesizing ⌘V — the user can confirm the
                    // refine and paste manually with one keystroke.
                    await PreviewPanel().show(
                        original: result.original,
                        refined: result.refined,
                        axWriteAvailable: false,
                        onAccept: { [weak self] in
                            guard let self else { return }
                            self.accessibility.applyTextWithFallback(result.refined)
                        },
                        onReject: { [weak self] in
                            guard let self else { return }
                            Task { _ = try? await self.fixer.ring.popLatest() }
                            Log.info("right-cmd preview rejected — rolled back ring entry")
                        }
                    )
                } else {
                    applyRefined(result.refined)
                }
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
        accessibility.applyTextWithFallback(text)
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
