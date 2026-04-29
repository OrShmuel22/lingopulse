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
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        guard let sel = await accessibility.readOrFallback() else {
            Notifications.show(title: "LingoPulse", body: "No selection.")
            return
        }
        let selection = sel.text
        let capturedElement = sel.element

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
                    self.accessibility.applyTextWithFallback(result.refined, to: capturedElement)
                } catch {
                    Log.error("tone refine error: \(error)")
                    Notifications.show(title: "LingoPulse", body: "Refine failed: \(error)")
                }
            }
        }
    }
}
