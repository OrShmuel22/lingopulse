import AppKit

@MainActor
final class ToneCommand {
    static let availableTones: [String] = ["Casual", "Neutral", "Technical", "Professional", "Grammar-only"]

    private let fixer: Fixer
    private let accessibility: AccessibilityServicing
    private let overrides: ToneOverrides

    init(fixer: Fixer, accessibility: AccessibilityServicing, overrides: ToneOverrides = ToneOverrides()) {
        self.fixer = fixer
        self.accessibility = accessibility
        self.overrides = overrides
    }

    func execute() async {
        let selection: String
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        if let sel = accessibility.readSelection() {
            selection = sel.text
        } else if let fb = await accessibility.pasteboardFallbackRead(), !fb.isEmpty {
            selection = fb
        } else {
            Notifications.show(title: "LingoPulse", body: "No selection.")
            return
        }

        let preselected = overrides.tone(for: app) ?? "Neutral"

        await TonePickerPanel().show(
            tones: Self.availableTones,
            preselected: preselected
        ) { [weak self] picked in
            guard let self = self else { return }
            Task { @MainActor in
                self.overrides.setTone(picked, for: app)
                do {
                    let result = try await self.fixer.refine(selection: selection, app: app, toneOverride: picked)
                    self.applyRefined(result.refined)
                } catch {
                    Log.error("tone refine error: \(error)")
                    Notifications.show(title: "LingoPulse", body: "Refine failed: \(error)")
                }
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
}
