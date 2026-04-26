import AppKit
import ApplicationServices

@MainActor
final class AppCoordinator {
    let fixer: Fixer
    let daemonClient: DaemonClient
    private let accessibility: AccessibilityServicing
    private let pipeline: SuggestionPipelining
    private let reviewPresenter: ReviewPresenting
    private let toast = AffirmationToast()
    private var lastDaemonDownNotice: Date?
    private var currentRefineTask: Task<Void, Never>?

    init(fixer: Fixer, daemon: DaemonClient, accessibility: AccessibilityServicing,
         pipeline: SuggestionPipelining, reviewPresenter: ReviewPresenting) {
        self.fixer = fixer
        self.daemonClient = daemon
        self.accessibility = accessibility
        self.pipeline = pipeline
        self.reviewPresenter = reviewPresenter
    }

    func updateDaemonURL(_ url: URL) { Log.info("daemon URL updated to \(url) — restart app to apply") }

    func fetchStatusAndShowAlert() {
        Log.info("fetchStatusAndShowAlert: daemon status check not wired in-process yet")
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

    func undoLast()            { Log.info("undo: not implemented yet") }
    func previewSelection()    { Log.info("preview: not implemented yet") }
    func refineWithTone()      { Log.info("tone: not implemented yet") }
    func lookupWord()          { Log.info("dictionary: not implemented yet") }
    func captureStyleExample() { Log.info("captureStyle: not implemented yet") }
}
