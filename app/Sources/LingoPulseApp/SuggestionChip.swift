import AppKit
import SwiftUI
import ApplicationServices

enum ChipPositioning {
    static func computeOrigin(
        elementBounds: CGRect,    // top-left origin (AX style)
        panelSize: CGSize,
        screenBounds: CGRect      // bottom-left origin (AppKit style)
    ) -> CGPoint {
        // AX-Y to Cocoa-Y: cocoaY = screenBounds.maxY - axY
        let elementBottomAX = elementBounds.maxY  // AX maxY = top + height
        let elementBottomCocoa = screenBounds.maxY - elementBottomAX
        let panelBottomY = elementBottomCocoa - panelSize.height - Constants.Layout.chipElementOffset

        var x = elementBounds.minX
        if x + panelSize.width > screenBounds.maxX - 8 {
            x = screenBounds.maxX - panelSize.width - 8
        }
        if x < screenBounds.minX + 8 {
            x = screenBounds.minX + 8
        }

        var y = panelBottomY
        if y < screenBounds.minY + 8 {
            let elementTopCocoa = screenBounds.maxY - elementBounds.minY
            y = elementTopCocoa + Constants.Layout.chipElementOffset
        }

        return CGPoint(x: x, y: y)
    }
}

final class SuggestionChip {
    private var window: NSPanel?
    private var hostingController: NSHostingController<ChipView>?
    private var dismissTimer: Timer?
    private var pendingShowElement: AXUIElement?

    var originalText: String = ""
    var refinedText: String = ""
    var acceptedIndices: Set<Int> = []
    private(set) var currentIndex: Int = 0
    private(set) var allEdits: [Edit] = []
    var dismissedCount: Int { allEdits.count - acceptedIndices.count }
    var onNeverFix: ((String, String) -> Void)?
    var currentApp: String?

    func configure(edits: [Edit], original: String, refined: String) {
        allEdits = edits
        originalText = original
        refinedText = refined
        acceptedIndices = []
        currentIndex = 0
    }

    @MainActor func show(near element: AXUIElement?) {
        guard !allEdits.isEmpty else { return }

        if window != nil {
            pendingShowElement = element
            hide { [weak self] in
                guard let self = self, let pendingEl = self.pendingShowElement else { return }
                self.pendingShowElement = nil
                self.show(near: pendingEl)
            }
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 80),
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

        let chipView = makeChipView()
        let hc = NSHostingController(rootView: chipView)
        guard let contentBounds = panel.contentView?.bounds else { return }
        hc.view.frame = contentBounds
        hc.view.autoresizingMask = [.width, .height]
        hc.view.layer?.backgroundColor = .clear
        panel.contentView?.addSubview(hc.view)

        sizePanel(panel, hc: hc)

        // Compute origin AFTER sizing so we know the panel height for AppKit's
        // bottom-left origin coordinate.
        let panelSize = panel.frame.size
        let origin = chipOrigin(near: element, panelSize: panelSize)

        self.window = panel
        self.hostingController = hc

        panel.alphaValue = 0
        panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y - Constants.Layout.chipSlideOffset))
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Constants.Timing.chipShowAnimationSeconds
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
            panel.animator().setFrameOrigin(origin)
        }, completionHandler: nil)

        Log.debug("chip: shown at \(origin) size \(panelSize) edits=\(allEdits.count)")

        let dismissInterval = Preferences.shared.autoDismissSeconds
        dismissTimer = Timer.scheduledTimer(withTimeInterval: dismissInterval, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    func acceptCurrent() -> Bool {
        acceptedIndices.insert(currentIndex)
        let unaccepted = (0..<allEdits.count).filter { !acceptedIndices.contains($0) }
        if unaccepted.isEmpty {
            return true
        }
        currentIndex = unaccepted[0]
        rerender()
        return false
    }

    func cycleNext() {
        currentIndex = (currentIndex + 1) % allEdits.count
        rerender()
    }

    func cyclePrev() {
        currentIndex = (currentIndex - 1 + allEdits.count) % allEdits.count
        rerender()
    }

    func hide(completion: (() -> Void)? = nil) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard let window = window else { completion?(); return }
        self.window = nil
        self.hostingController = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Constants.Timing.chipHideAnimationSeconds
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            completion?()
        })
    }

    private func rerender() {
        guard let panel = window, let hc = hostingController else { return }
        let chipView = makeChipView()
        hc.rootView = chipView
        sizePanel(panel, hc: hc)
    }

    private func makeChipView() -> ChipView {
        let edit = allEdits[currentIndex]
        let countLabel: String? = allEdits.count > 1 ? "\(currentIndex + 1) of \(allEdits.count)" : nil
        return ChipView(edit: edit, countLabel: countLabel, onNeverFix: onNeverFix, currentApp: currentApp)
    }

    private func sizePanel(_ panel: NSPanel, hc: NSHostingController<ChipView>) {
        let fittingSize = hc.sizeThatFits(in: CGSize(width: Constants.Layout.chipMaxWidth, height: Constants.Layout.chipMaxHeight))
        let finalWidth = max(fittingSize.width, Constants.Layout.chipMinWidth)
        let finalHeight = max(fittingSize.height, Constants.Layout.chipMinHeight)
        panel.setContentSize(CGSize(width: finalWidth, height: finalHeight))
    }

    private func chipOrigin(near element: AXUIElement?, panelSize: CGSize) -> CGPoint {
        guard let element = element,
              let screen = NSScreen.main else {
            return fallbackOrigin(panelSize: panelSize)
        }

        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)

        guard let axTopLeft = AXClient.axPoint(from: posValue),
              let size = AXClient.axSize(from: sizeValue) else {
            return fallbackOrigin(panelSize: panelSize)
        }

        // AX uses top-left origin, AppKit uses bottom-left.
        // Place chip's TOP edge chipElementOffset below element's bottom.
        // In AppKit, panel frame origin is the bottom-left of the panel,
        // so we need: panelBottom = elementBottomInCocoa - panelHeight
        let elementBottomAX = axTopLeft.y + size.height
        let elementBottomCocoa = screen.frame.maxY - elementBottomAX
        let panelBottomY = elementBottomCocoa - panelSize.height - Constants.Layout.chipElementOffset

        // Clamp X within visible screen, leave chipSlideOffset margin
        var x = axTopLeft.x
        if x + panelSize.width > screen.frame.maxX - Constants.Layout.chipSlideOffset {
            x = screen.frame.maxX - panelSize.width - Constants.Layout.chipSlideOffset
        }
        if x < screen.frame.minX + Constants.Layout.chipSlideOffset {
            x = screen.frame.minX + Constants.Layout.chipSlideOffset
        }

        // If chip would go below screen, place it ABOVE the element instead
        var y = panelBottomY
        if y < screen.frame.minY + Constants.Layout.chipSlideOffset {
            let elementTopCocoa = screen.frame.maxY - axTopLeft.y
            y = elementTopCocoa + Constants.Layout.chipElementOffset
        }

        return CGPoint(x: x, y: y)
    }

    private func fallbackOrigin(panelSize: CGSize) -> CGPoint {
        guard let screen = NSScreen.main else { return CGPoint(x: 100, y: 100) }
        return CGPoint(
            x: screen.frame.maxX - panelSize.width - Constants.Layout.chipScreenMargin,
            y: screen.frame.maxY - panelSize.height - Constants.Layout.chipScreenMargin * 2.5
        )
    }
}

struct ChipView: View {
    let edit: Edit
    let countLabel: String?
    let onNeverFix: ((String, String) -> Void)?
    let currentApp: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(edit.from_text)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                    .contextMenu {
                        Button("Never fix '\(edit.from_text)' anywhere") {
                            onNeverFix?(edit.from_text, "*")
                        }
                        if let app = currentApp, !app.isEmpty {
                            Button("Never fix '\(edit.from_text)' in \(app)") {
                                onNeverFix?(edit.from_text, app)
                            }
                        }
                    }
                Text("→")
                    .foregroundColor(.secondary)
                Text(edit.to_text)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                categoryPill(edit.categoryEnum)
            }
            HStack(spacing: 4) {
                if let label = countLabel {
                    Text(label)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("·")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text("Tab accept · ↓↑ navigate · Esc dismiss")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .padding(4)
    }

    private func categoryPill(_ category: EditCategory) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(categoryColor(category))
            .frame(height: 20)
            .overlay(
                Text(category.rawValue.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
            )
            .fixedSize()
    }

    private func categoryColor(_ category: EditCategory) -> Color {
        switch category {
        case .preposition, .comparative: return Color.blue.opacity(0.85)
        case .plural:                    return Color.green.opacity(0.85)
        case .calque:                    return Color.orange.opacity(0.85)
        case .structure:                 return Color.purple.opacity(0.85)
        case .typo:                      return Color.red.opacity(0.85)
        case .apostrophe:                return Color(.darkGray)
        case .capitalization:            return Color.teal.opacity(0.85)
        case .grammar, .other:           return Color.gray
        }
    }
}
