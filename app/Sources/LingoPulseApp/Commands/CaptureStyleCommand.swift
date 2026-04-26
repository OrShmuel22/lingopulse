import AppKit

@MainActor
final class CaptureStyleCommand {
    private let store: StyleExamplesStore
    private let accessibility: AccessibilityServicing

    init(store: StyleExamplesStore, accessibility: AccessibilityServicing) {
        self.store = store
        self.accessibility = accessibility
    }

    func execute() async {
        let text: String?
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"

        if let sel = accessibility.readSelection() {
            text = sel.text
        } else {
            text = await accessibility.pasteboardFallbackRead()
        }

        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
            Notifications.show(title: "LingoPulse", body: "Select text first to save as style example.")
            return
        }

        do {
            try await store.append([
                "text": t,
                "app": appName,
            ])
            Notifications.show(title: "LingoPulse", body: "Style example saved.")
        } catch {
            Log.error("captureStyle error: \(error)")
            Notifications.show(title: "LingoPulse", body: "Failed to save style example: \(error)")
        }
    }
}
