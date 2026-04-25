import AppKit
import ApplicationServices

@MainActor
final class AppCoordinator {
    private(set) var daemon: DaemonClient
    var daemonClient: DaemonClient { daemon }
    private let liveObserver = AXLiveObserver()
    private let debouncer = Debouncer(interval: Constants.Timing.debounceSeconds)
    private let chip = SuggestionChip()
    private let keyMonitor = KeyMonitor()
    private var inFlight = false
    private var coldStartShown = false
    private var lastDaemonDownNotice: Date?
    private var currentRefineTask: Task<Void, Never>?

    init(daemon: DaemonClient) {
        self.daemon = daemon
    }

    func startLiveListener() {
        liveObserver.onTextChange = { [weak self] text, app, element in
            guard let self = self else { return }
            self.debouncer.schedule {
                Task { @MainActor in
                    self.handleDebouncedText(text: text, app: app, element: element)
                }
            }
        }
        liveObserver.start()
    }

    func stopLiveListener() {
        liveObserver.stop()
        debouncer.cancel()
        currentRefineTask?.cancel()
        chip.hide()
        keyMonitor.stop()
    }

    func updateDaemonURL(_ url: URL) {
        self.daemon = DaemonClient(baseURL: url)
        Log.info("daemon URL updated to \(url)")
    }

    private func handleDebouncedText(text: String, app: String, element: AXUIElement) {
        guard !inFlight else { return }
        guard text.split(separator: " ").count >= Constants.Refine.minWordsForLiveTrigger else { return }
        inFlight = true
        currentRefineTask?.cancel()
        currentRefineTask = Task { @MainActor in
            defer { self.inFlight = false }
            do {
                let start = Date()
                let resp = try await daemon.refine(selection: text, app: app, toneOverride: nil)
                if Task.isCancelled { return }
                let elapsed = Date().timeIntervalSince(start)
                if elapsed > Constants.Timing.coldStartThresholdSeconds {
                    self.showColdStartNotice()
                }
                guard !resp.edits.isEmpty else { return }
                self.showChip(edits: resp.edits, original: text, refined: resp.refined, app: app, element: element)
            } catch {
                if Task.isCancelled { return }
                Log.error("live: refine error \(error)")
                self.showDaemonDownIfFresh()
            }
        }
    }

    private func showColdStartNotice() {
        guard !coldStartShown else { return }
        coldStartShown = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Timing.notificationCooldownSeconds) { [weak self] in
            self?.coldStartShown = false
        }
        Notifications.show(title: "LingoPulse", body: "Warming up gemma3 — next refine will be fast.")
    }

    private func showDaemonDownIfFresh() {
        if let last = lastDaemonDownNotice,
           Date().timeIntervalSince(last) < Constants.Timing.notificationCooldownSeconds { return }
        lastDaemonDownNotice = Date()
        Notifications.show(title: "LingoPulse", body: "Daemon unreachable. Check launchctl list | grep lingopulse.")
    }

    private func showChip(edits: [Edit], original: String, refined: String, app: String, element: AXUIElement) {
        chip.configure(edits: edits, original: original, refined: refined)
        chip.currentApp = app
        chip.onNeverFix = { [weak self] token, scope in
            Task {
                _ = try? await self?.daemon.addPersonalDictEntry(token: token, scope: scope)
                Log.info("never-fix added \(token) scope=\(scope)")
            }
        }
        chip.show(near: element)

        keyMonitor.onTab = { [weak self] in
            Task { await self?.acceptCurrentEdit(app: app) }
        }
        keyMonitor.onEsc = { [weak self] in
            guard let self = self else { return }
            self.dismissAndFeedback(
                input: original,
                rejected: refined,
                app: app,
                dismissedCount: self.chip.dismissedCount
            )
        }
        keyMonitor.onArrowDown = { [weak self] in self?.chip.cycleNext() }
        keyMonitor.onArrowUp = { [weak self] in self?.chip.cyclePrev() }
        keyMonitor.onOtherKey = { [weak self] in
            self?.chip.hide()
            self?.keyMonitor.stop()
        }
        keyMonitor.start()
    }

    private func acceptCurrentEdit(app: String) async {
        let isLast = chip.acceptCurrent()
        do {
            let response = try await daemon.applyEdits(
                original: chip.originalText,
                refined: chip.refinedText,
                acceptedIndices: Array(chip.acceptedIndices)
            )
            if isLast {
                self.applyFinalAndCleanup(text: response.result, app: app)
            }
        } catch {
            Log.error("apply_edits error \(error)")
        }
    }

    private func applyFinalAndCleanup(text: String, app: String) {
        if AppKind.fromAppName(app).isTerminal {
            pasteViaClipboard(text)
        } else if !AXClient.writeFocusedValue(text) {
            pasteViaClipboard(text)
        }
        chip.hide()
        keyMonitor.stop()
    }

    private func dismissAndFeedback(input: String, rejected: String, app: String, dismissedCount: Int) {
        Task {
            _ = try? await daemon.feedback(
                input: input,
                rejected: rejected,
                reason: "other",
                app: app,
                tone: "",
                note: "dismissed \(dismissedCount) edits via Esc"
            )
        }
        chip.hide()
        keyMonitor.stop()
    }

    func refineFocusedSelection() {
        guard let (text, app) = AXClient.readSelection() else {
            if !AXIsProcessTrusted() {
                Notifications.show(title: "LingoPulse", body: "Accessibility permission revoked. Re-enable in System Settings → Privacy → Accessibility.")
            }
            Log.error("no selection or AX denied.")
            return
        }
        Log.info("refining \(text.count) chars from \(app)")

        Task { @MainActor in
            do {
                let start = Date()
                let resp = try await daemon.refine(selection: text, app: app, toneOverride: nil)
                let elapsed = Date().timeIntervalSince(start)
                if elapsed > Constants.Timing.coldStartThresholdSeconds {
                    self.showColdStartNotice()
                }
                Log.info("\(resp.edits.count) edits returned")
                Log.debug("  ORIGINAL: \(resp.original)")
                Log.debug("  REFINED:  \(resp.refined)")
                for e in resp.edits {
                    Log.debug("  - [\(e.category)] \(e.from_text) → \(e.to_text)")
                }
                if AppKind.fromAppName(app).isTerminal {
                    Log.info("\(app) is a terminal — copying to clipboard (AX write unreliable)")
                    self.pasteViaClipboard(resp.refined)
                } else if AXClient.writeFocusedValue(resp.refined) {
                    Log.info("pasted via AX write")
                } else {
                    Log.info("AX write failed, copying to clipboard")
                    self.pasteViaClipboard(resp.refined)
                }
            } catch DaemonError.http(409) {
                Log.info("busy (another refine in flight) — try again in a moment")
            } catch {
                Log.error("refine error: \(error)")
                self.showDaemonDownIfFresh()
            }
        }
    }

    func fetchStatusAndShowAlert() {
        Task { @MainActor in
            do {
                let s = try await daemon.status()
                Log.info("status: model=\(s.model) loaded=\(s.model_loaded)")
                Notifications.show(title: "Daemon", body: "model=\(s.model) loaded=\(s.model_loaded)")
            } catch {
                Log.error("status error: \(error)")
            }
        }
    }

    private func pasteViaClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
