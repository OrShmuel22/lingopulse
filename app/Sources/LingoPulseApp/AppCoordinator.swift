import AppKit

final class AppCoordinator {
    private let daemon: DaemonClient

    init(daemon: DaemonClient) {
        self.daemon = daemon
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
