import AppKit
import SwiftUI
import ApplicationServices

final class SuggestionChip {
    private var window: NSPanel?
    private var hostingController: NSHostingController<ChipView>?
    private var dismissTimer: Timer?
    var onAccept: ((Int) -> Void)?
    var onDismiss: (() -> Void)?

    func show(edits: [Edit], near element: AXUIElement?) {
        guard let firstEdit = edits.first else { return }

        hide()

        let origin = elementOrigin(element)

        let panel = NSPanel(
            contentRect: NSRect(x: origin.x, y: origin.y, width: 360, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false

        let chipView = ChipView(
            edit: firstEdit,
            onAccept: { [weak self] in self?.onAccept?(0) },
            onDismiss: { [weak self] in self?.onDismiss?() }
        )

        let hc = NSHostingController(rootView: chipView)
        hc.view.frame = panel.contentView!.bounds
        hc.view.autoresizingMask = [.width, .height]
        hc.view.layer?.backgroundColor = .clear
        panel.contentView?.addSubview(hc.view)

        let fittingSize = hc.sizeThatFits(in: CGSize(width: 400, height: 200))
        let finalWidth = max(fittingSize.width, 240)
        let finalHeight = max(fittingSize.height, 64)
        panel.setContentSize(CGSize(width: finalWidth, height: finalHeight))
        panel.setFrameOrigin(origin)

        self.window = panel
        self.hostingController = hc

        panel.orderFront(nil)

        dismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.onDismiss?()
        }
    }

    func hide() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        window?.orderOut(nil)
        window = nil
        hostingController = nil
    }

    private func elementOrigin(_ element: AXUIElement?) -> CGPoint {
        guard let element = element else { return fallbackOrigin() }

        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)

        guard let pv = posValue, let sv = sizeValue else { return fallbackOrigin() }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &point),
              AXValueGetValue(sv as! AXValue, .cgSize, &size) else { return fallbackOrigin() }

        let axY = point.y + size.height + 4
        let cocoaY = NSScreen.main!.frame.maxY - axY
        return CGPoint(x: point.x, y: cocoaY)
    }

    private func fallbackOrigin() -> CGPoint {
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: mouse.x + 8, y: mouse.y - 28)
    }
}

struct ChipView: View {
    let edit: Edit
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(edit.from_text)
                    .strikethrough()
                    .foregroundColor(.secondary)
                Text("→")
                    .foregroundColor(.secondary)
                Text(edit.to_text)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                Text(edit.category)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.25))
                    .clipShape(Capsule())
            }
            Text("Tab accept · Esc dismiss")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .padding(4)
    }
}
