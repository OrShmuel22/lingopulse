import AppKit
import ApplicationServices

final class AppCoordinator {
    let daemon: DaemonClient
    var daemonClient: DaemonClient { daemon }
    private let liveObserver = AXLiveObserver()
    private let debouncer = Debouncer(interval: 1.5)
    private let chip = SuggestionChip()
    private let keyMonitor = KeyMonitor()
    private var inFlight = false

    init(daemon: DaemonClient) {
        self.daemon = daemon
    }

    func startLiveListener() {
        liveObserver.onTextChange = { [weak self] text, app, element in
            guard let self = self else { return }
            self.debouncer.schedule {
                self.handleDebouncedText(text: text, app: app, element: element)
            }
        }
        liveObserver.start()
    }

    private func handleDebouncedText(text: String, app: String, element: AXUIElement) {
        guard !inFlight else { return }
        guard text.split(separator: " ").count >= 3 else { return }
        inFlight = true
        Task {
            defer { Task { @MainActor in self.inFlight = false } }
            do {
                let resp = try await daemon.refine(selection: text, app: app, toneOverride: nil)
                guard !resp.edits.isEmpty else { return }
                await MainActor.run {
                    self.showChip(edits: resp.edits, original: text, refined: resp.refined, app: app, element: element)
                }
            } catch {
                NSLog("LingoPulse live: refine error \(error)")
            }
        }
    }

    private func showChip(edits: [Edit], original: String, refined: String, app: String, element: AXUIElement) {
        chip.configure(edits: edits, original: original, refined: refined)
        chip.currentApp = app
        chip.onNeverFix = { [weak self] token, scope in
            Task {
                try? await self?.daemon.addPersonalDictEntry(token: token, scope: scope)
                NSLog("LingoPulse: never-fix added \(token) scope=\(scope)")
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
                await MainActor.run { self.applyFinalAndCleanup(text: response.result, app: app) }
            }
        } catch {
            NSLog("LingoPulse: apply_edits error \(error)")
        }
    }

    private func applyFinalAndCleanup(text: String, app: String) {
        let isTerminal = ["iTerm2", "Terminal", "Alacritty", "WezTerm", "Hyper", "Warp"].contains(app)
        if isTerminal {
            pasteViaClipboard(text)
        } else if !AXClient.writeFocusedValue(text) {
            pasteViaClipboard(text)
        }
        chip.hide()
        keyMonitor.stop()
    }

    private func dismissAndFeedback(input: String, rejected: String, app: String, dismissedCount: Int) {
        Task {
            try? await daemon.feedback(
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
            NSLog("LingoPulse: no selection or AX denied.")
            return
        }
        NSLog("LingoPulse: refining \(text.count) chars from \(app)")

        Task {
            do {
                let resp = try await daemon.refine(selection: text, app: app, toneOverride: nil)
                NSLog("LingoPulse: \(resp.edits.count) edits returned")
                NSLog("LingoPulse:   ORIGINAL: \(resp.original)")
                NSLog("LingoPulse:   REFINED:  \(resp.refined)")
                for e in resp.edits {
                    NSLog("  - [\(e.category)] \(e.from_text) → \(e.to_text)")
                }
                let isTerminal = ["iTerm2", "Terminal", "Alacritty", "WezTerm", "Hyper", "Warp"].contains(app)
                if isTerminal {
                    NSLog("LingoPulse: \(app) is a terminal — copying to clipboard (AX write unreliable)")
                    pasteViaClipboard(resp.refined)
                } else if AXClient.writeFocusedValue(resp.refined) {
                    NSLog("LingoPulse: pasted via AX write")
                } else {
                    NSLog("LingoPulse: AX write failed, copying to clipboard")
                    pasteViaClipboard(resp.refined)
                }
            } catch DaemonError.http(409) {
                NSLog("LingoPulse: busy (another refine in flight) — try again in a moment")
            } catch {
                NSLog("LingoPulse: refine error: \(error)")
            }
        }
    }

    func fetchStatusAndShowAlert() {
        Task {
            do {
                let s = try await daemon.status()
                NSLog("LingoPulse status: model=\(s.model) loaded=\(s.model_loaded)")
                await MainActor.run {
                    showToast(title: "Daemon", body: "model=\(s.model) loaded=\(s.model_loaded)")
                }
            } catch {
                NSLog("LingoPulse status error: \(error)")
            }
        }
    }

    private func pasteViaClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func showToast(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
