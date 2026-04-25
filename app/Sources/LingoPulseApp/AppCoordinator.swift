import AppKit
import ApplicationServices

@MainActor
final class AppCoordinator {
    let daemonClient: DaemonClient
    private let accessibility: AccessibilityServicing
    private let pipeline: SuggestionPipelining
    private let reviewPresenter: ReviewPresenting
    private let toast = AffirmationToast()
    private var coldStartShown: Date?
    private var lastDaemonDownNotice: Date?
    private var currentRefineTask: Task<Void, Never>?

    init(daemon: DaemonClient, accessibility: AccessibilityServicing,
         pipeline: SuggestionPipelining, reviewPresenter: ReviewPresenting) {
        self.daemonClient = daemon
        self.accessibility = accessibility
        self.pipeline = pipeline
        self.reviewPresenter = reviewPresenter
    }

    func updateDaemonURL(_ url: URL) { Log.info("daemon URL updated to \(url) — restart app to apply") }

    func refineFocusedSelection() {
        guard let selection = accessibility.readSelection() else {
            if !accessibility.isTrusted {
                Notifications.show(title: "LingoPulse", body: "Accessibility permission revoked. Re-enable in System Settings → Privacy → Accessibility.")
            }
            Log.error("no selection or AX denied.")
            return
        }
        Log.info("refining \(selection.text.count) chars from \(selection.appName)")
        handleSelection(selection, manual: true)
    }

    func fetchStatusAndShowAlert() {
        Task { @MainActor in
            do {
                let s = try await daemonClient.status()
                Log.info("status: model=\(s.model) loaded=\(s.model_loaded)")
                Notifications.show(title: "Daemon", body: "model=\(s.model) loaded=\(s.model_loaded)")
            } catch { Log.error("status error: \(error)") }
        }
    }

    private func handleSelection(_ selection: Selection, manual: Bool) {
        if !manual && selection.text.split(separator: " ").count < Constants.Refine.minWordsForLiveTrigger { return }
        currentRefineTask?.cancel()
        currentRefineTask = Task { @MainActor in
            do {
                let start = Date()
                let result = try await pipeline.requestSuggestions(for: selection)
                if Date().timeIntervalSince(start) > Constants.Timing.coldStartThresholdSeconds { showColdStartNotice() }
                if Task.isCancelled { return }

                if manual {
                    if let result = result {
                        applyDirect(refined: result.refined, app: selection.appKind)
                    }
                    return
                }

                guard let result = result else {
                    toast.show()
                    return
                }

                reviewPresenter.present(
                    result: result,
                    in: selection.appKind,
                    near: selection.element,
                    onAccept: { [weak self] indices in
                        Task { @MainActor in
                            guard let self = self else { return }
                            do {
                                let text = try await self.pipeline.applyAccepted(
                                    original: result.original,
                                    refined: result.refined,
                                    indices: indices
                                )
                                self.applyDirect(refined: text, app: selection.appKind)
                                self.reviewPresenter.dismiss()
                            } catch { Log.error("apply_edits error \(error)") }
                        }
                    },
                    onDismiss: { [weak self] count in
                        Task { @MainActor in
                            guard let self = self else { return }
                            await self.pipeline.sendDismissalFeedback(
                                input: result.original,
                                rejected: result.refined,
                                app: selection.appKind,
                                dismissedCount: count
                            )
                            self.reviewPresenter.dismiss()
                        }
                    }
                )

            } catch is CancellationError { return
            } catch DaemonError.http(409) { Log.info("busy — try again in a moment")
            } catch { Log.error("refine error: \(error)"); showDaemonDownIfFresh() }
        }
    }

    private func applyDirect(refined: String, app: AppKind) {
        if app.isTerminal || !accessibility.writeFocusedValue(refined) { pasteViaClipboard(refined) }
    }

    private func pasteViaClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func showColdStartNotice() {
        if let last = coldStartShown, Date().timeIntervalSince(last) < Constants.Timing.notificationCooldownSeconds { return }
        coldStartShown = Date()
        Notifications.show(title: "LingoPulse", body: "Warming up — next refine will be fast.")
    }

    private func showDaemonDownIfFresh() {
        if let last = lastDaemonDownNotice, Date().timeIntervalSince(last) < Constants.Timing.notificationCooldownSeconds { return }
        lastDaemonDownNotice = Date()
        Notifications.show(title: "LingoPulse", body: "Daemon unreachable. Check launchctl list | grep lingopulse.")
    }
}
