import AppKit
import SwiftUI

@MainActor
final class GhostOverlayWindow {
    private var window: GhostPanel?
    private var fadeTask: Task<Void, Never>?

    func show(suggestion: LiveSuggestion, onApply: @escaping () -> Void) {
        close()

        let view = GhostOverlayView(
            original: suggestion.original,
            refined: suggestion.refined,
            onApply: { [weak self] in
                self?.close()
                onApply()
            },
            onDismiss: { [weak self] in self?.close() }
        )
        let hc = NSHostingController(rootView: view)
        hc.view.frame = NSRect(x: 0, y: 0, width: 380, height: 140)

        let panel = GhostPanel(
            contentRect: hc.view.frame,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hc
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false

        var origin = CGPoint(x: 100, y: 100)
        if let anchor = suggestion.anchorRect {
            origin = CGPoint(x: anchor.origin.x, y: anchor.origin.y - 150)
            if let screen = NSScreen.main?.frame {
                origin.x = max(8, min(origin.x, screen.maxX - 388))
                origin.y = max(8, min(origin.y, screen.maxY - 148))
            }
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        self.window = panel

        fadeTask?.cancel()
        fadeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self.close()
        }
    }

    func close() {
        fadeTask?.cancel()
        fadeTask = nil
        window?.orderOut(nil)
        window = nil
    }
}

private final class GhostPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct GhostOverlayView: View {
    let original: String
    let refined: String
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested:").font(.caption).foregroundStyle(.secondary)
            Text(refined)
                .font(.callout)
                .lineLimit(3)
                .padding(.bottom, 2)
            HStack {
                Spacer()
                Button("Dismiss") { onDismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Apply") { onApply() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .cornerRadius(10)
    }
}
