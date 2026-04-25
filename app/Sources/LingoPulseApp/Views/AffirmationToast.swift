import AppKit
import SwiftUI

@MainActor
final class AffirmationToast {
    private var window: NSPanel?
    private var dismissTimer: Timer?

    func show() {
        hide()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 50),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false

        let view = AffirmationToastView()
        let hc = NSHostingController(rootView: view)
        let fittingSize = hc.sizeThatFits(in: CGSize(width: 240, height: 60))
        panel.setContentSize(fittingSize)
        panel.contentView?.addSubview(hc.view)
        hc.view.frame = panel.contentView?.bounds ?? .zero
        hc.view.autoresizingMask = [.width, .height]

        guard let screen = NSScreen.main else { return }
        let origin = CGPoint(
            x: screen.frame.maxX - panel.frame.width - Constants.Layout.chipScreenMargin,
            y: screen.frame.maxY - panel.frame.height - 60
        )
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Constants.Timing.chipShowAnimationSeconds
            panel.animator().alphaValue = 1.0
        }, completionHandler: nil)

        self.window = panel

        dismissTimer = Timer.scheduledTimer(withTimeInterval: Constants.Timing.affirmationDismissSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func hide() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard let panel = window else { return }
        self.window = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Constants.Timing.chipHideAnimationSeconds
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }
}

struct AffirmationToastView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 18, weight: .semibold))
            Text("Looks good")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
        )
        .padding(4)
    }
}
