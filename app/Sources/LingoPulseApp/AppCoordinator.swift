import AppKit
import ApplicationServices

@MainActor
final class AppCoordinator {
    let daemonClient: DaemonClient
    private let accessibility: AccessibilityServicing
    private let pipeline: SuggestionPipelining
    private let presenter: ChipPresenting
    private let debouncer: Debouncer
    private var coldStartShown: Date?
    private var lastDaemonDownNotice: Date?
    private var currentRefineTask: Task<Void, Never>?

    init(daemon: DaemonClient, accessibility: AccessibilityServicing,
         pipeline: SuggestionPipelining, presenter: ChipPresenting) {
        self.daemonClient = daemon
        self.accessibility = accessibility
        self.pipeline = pipeline
        self.presenter = presenter
        self.debouncer = Debouncer(interval: Constants.Timing.debounceSeconds)
    }

    func updateDaemonURL(_ url: URL) { Log.info("daemon URL updated to \(url) — restart app to apply") }

    func startLiveListener() {
        accessibility.startListening { [weak self] selection in
            self?.debouncer.schedule {
                Task { @MainActor in self?.handleSelection(selection, manual: false) }
            }
        }
    }

    func stopLiveListener() {
        accessibility.stopListening()
        debouncer.cancel()
        presenter.dismiss()
        pipeline.cancelInFlight()
        currentRefineTask?.cancel()
    }

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
                guard let result = try await pipeline.requestSuggestions(for: selection) else { return }
                if Date().timeIntervalSince(start) > Constants.Timing.coldStartThresholdSeconds { showColdStartNotice() }
                if Task.isCancelled { return }
                if manual { applyDirect(refined: result.refined, app: selection.appKind) }
                else { showChip(result: result, selection: selection) }
            } catch is CancellationError { return
            } catch DaemonError.http(409) { Log.info("busy — try again in a moment")
            } catch { Log.error("refine error: \(error)"); showDaemonDownIfFresh() }
        }
    }

    private func showChip(result: RefineResult, selection: Selection) {
        presenter.present(result: result, in: selection.appKind, near: selection.element) { [weak self] action in
            self?.handleChipAction(action, selection: selection)
        }
    }

    private func handleChipAction(_ action: ChipAction, selection: Selection) {
        switch action {
        case .acceptCurrent(_, let isLast):
            let state = presenter.chipState()
            Task { @MainActor in
                do {
                    let text = try await pipeline.applyAccepted(original: state.original, refined: state.refined, indices: Array(state.acceptedIndices))
                    if isLast { applyDirect(refined: text, app: selection.appKind); presenter.dismiss() }
                } catch { Log.error("apply_edits error \(error)") }
            }
        case .dismissed(let count):
            Task { await pipeline.sendDismissalFeedback(input: selection.text, rejected: selection.text, app: selection.appKind, dismissedCount: count) }
        case .neverFix(let token, let scope):
            Task { _ = try? await daemonClient.addPersonalDictEntry(token: token, scope: scope); Log.info("never-fix: \(token) scope=\(scope)") }
        case .cycleNext, .cyclePrev: break
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
