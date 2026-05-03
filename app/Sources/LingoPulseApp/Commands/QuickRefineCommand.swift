import AppKit

@MainActor
final class QuickRefineCommand {
    typealias Capture = @MainActor () async -> String?
    typealias TonePick = @MainActor () async -> String?
    typealias ShowPreview = @MainActor (FixerResult, @escaping () -> Void, @escaping () -> Void) async -> Void

    private let fixer: Fixer
    private let capture: Capture
    private let tonePick: TonePick
    private let showPreview: ShowPreview
    private let notify: (String, String) -> Void

    init(
        fixer: Fixer,
        capture: @escaping Capture = QuickRefineCommand.defaultCapture,
        tonePick: @escaping TonePick = QuickRefineCommand.defaultTonePick,
        showPreview: @escaping ShowPreview = QuickRefineCommand.defaultShowPreview,
        notify: @escaping (String, String) -> Void = { title, body in
            Notifications.show(title: title, body: body)
        }
    ) {
        self.fixer = fixer
        self.capture = capture
        self.tonePick = tonePick
        self.showPreview = showPreview
        self.notify = notify
    }

    func execute() async {
        guard let text = await capture() else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let tone = await tonePick() else { return }

        let result: FixerResult
        do {
            result = try await fixer.refine(
                selection: trimmed,
                app: Constants.AppNames.quickRefine,
                toneOverride: tone
            )
        } catch FixerError.ollama(.busy) {
            Log.info("ollama busy — try again in a moment")
            return
        } catch FixerError.ollama(.timeout) {
            notify("LingoPulse", "Refinement timed out. Model may be cold.")
            return
        } catch {
            Log.error("quick refine error: \(error)")
            notify("LingoPulse", "Refine failed: \(error)")
            return
        }

        await showPreview(
            result,
            { /* accept = no-op; preview already auto-copied refined text */ },
            { [weak fixer] in
                Task { _ = try? await fixer?.ring.popLatest() }
                Log.info("quick refine preview rejected — rolled back ring entry")
            }
        )
    }

    static func defaultCapture() async -> String? {
        await withCheckedContinuation { cont in
            let panel = QuickRefineCapturePanel()
            panel.show { text in
                cont.resume(returning: text)
            }
        }
    }

    static func defaultTonePick() async -> String? {
        await withCheckedContinuation { cont in
            Task { @MainActor in
                var resolved = false
                await TonePickerPanel().show(
                    tones: ToneCommand.availableTones,
                    preselected: "Grammar-only",
                    onCancel: {
                        if !resolved { resolved = true; cont.resume(returning: nil) }
                    }
                ) { picked in
                    if !resolved { resolved = true; cont.resume(returning: picked) }
                }
            }
        }
    }

    static func defaultShowPreview(
        _ result: FixerResult,
        _ onAccept: @escaping () -> Void,
        _ onReject: @escaping () -> Void
    ) async {
        await PreviewPanel().show(
            original: result.original,
            refined: result.refined,
            axWriteAvailable: false,
            onAccept: onAccept,
            onReject: onReject
        )
    }
}
