import AppKit
import SwiftUI
import LingoPulseIMECore

// MARK: - SuggestionWindow

/// A floating NSPanel that shows grammar / style suggestions near the caret.
///
/// Coordinate-space note:
///   IMKTextInput.attributes(forCharacterIndex:lineHeightRectangle:) returns the
///   line-height rect in **AppKit screen coordinates** (origin = bottom-left of
///   primary display, Y increases upward). That rect can be passed directly to
///   NSWindow.setFrameOrigin(_:) / NSWindow.cascadeTopLeft(from:) since those
///   methods also work in screen coordinates.
///   The panel is positioned *below* the caret line by default; if there is not
///   enough vertical space below (< panel height + margin) it flips above.
///
/// Auto-dismiss:
///   The panel dismisses itself after 8 seconds unless the caller calls hide()
///   first.
///
/// Multi-edit cycling:
///   Up/Down arrow keys cycle `selectedIndex` over the edit list.  The controller
///   reads `selectedIndex` via `currentIndex` and calls `cycleUp()` / `cycleDown()`.
///
/// Callbacks:
///   `onAccept` — called with the index to accept when Tab is pressed.
///   `onDismiss` — called when Escape is pressed.
final class SuggestionWindow: NSObject {

    // MARK: - Constants

    private enum Layout {
        static let panelWidth: CGFloat = 340
        static let panelMaxHeight: CGFloat = 260
        static let caretGap: CGFloat = 6      // pixels below the caret rect
        static let screenMargin: CGFloat = 12 // minimum distance from screen edge
    }

    private enum Timing {
        static let autoDismiss: TimeInterval = 8
        static let fadeIn: TimeInterval = 0.15
        static let fadeOut: TimeInterval = 0.10
    }

    // MARK: - State

    /// The edit list currently displayed.  Non-empty when the panel is visible.
    private(set) var edits: [IMEEdit] = []

    /// 0-based index of the currently highlighted edit (for Tab-accept and display).
    private(set) var selectedIndex: Int = 0

    // MARK: - Internals

    private var panel: NSPanel?
    private var hostingView: NSHostingView<SuggestionView>?
    private var dismissTask: DispatchWorkItem?

    // MARK: - Callbacks (set by the controller before calling show)

    /// Called with the `selectedIndex` when Tab is pressed and the panel is visible.
    var onAccept: ((Int) -> Void)?

    /// Called when Escape is pressed and the panel is visible.
    var onDismiss: (() -> Void)?

    // MARK: - Public API

    /// Show suggestions near the given caret rectangle (screen coordinates).
    /// If `caretScreenRect` is `.zero` the panel falls back to screen centre.
    func show(edits: [IMEEdit], caretScreenRect: NSRect) {
        hide() // dismiss any previous panel before creating a new one

        guard !edits.isEmpty else { return }

        self.edits = edits
        self.selectedIndex = 0

        let content = SuggestionView(edits: edits, selectedIndex: 0)
        let hv = NSHostingView(rootView: content)
        hv.frame = NSRect(x: 0, y: 0,
                          width: Layout.panelWidth,
                          height: Layout.panelMaxHeight)

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0,
                                width: Layout.panelWidth,
                                height: Layout.panelMaxHeight),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.contentView = hv
        newPanel.ignoresMouseEvents = false

        let origin = panelOrigin(caretRect: caretScreenRect,
                                 panelSize: NSSize(width: Layout.panelWidth,
                                                   height: Layout.panelMaxHeight))
        newPanel.setFrameOrigin(origin)

        // Fade in
        newPanel.alphaValue = 0
        newPanel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Timing.fadeIn
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            newPanel.animator().alphaValue = 1.0
        }

        panel = newPanel
        hostingView = hv

        // Schedule auto-dismiss
        let task = DispatchWorkItem { [weak self] in self?.hide() }
        dismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.autoDismiss,
                                      execute: task)

        IMELog.info("SuggestionWindow shown (\(edits.count) edit(s)) at \(origin)")
    }

    /// Hide and tear down the panel immediately.
    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        edits = []
        selectedIndex = 0
        guard let dyingPanel = panel else { return }
        panel = nil
        hostingView = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Timing.fadeOut
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            dyingPanel.animator().alphaValue = 0
        }, completionHandler: {
            dyingPanel.orderOut(nil)
        })
    }

    // MARK: - Key handling (called by didCommand in the controller)

    /// Tab pressed: accept the currently selected edit.
    func handleTabKey() {
        guard isVisible else { return }
        let idx = selectedIndex
        IMELog.info("Tab — accepting edit[\(idx)]")
        onAccept?(idx)
        // The controller hides the panel after replacing text.
    }

    /// Escape pressed: dismiss suggestion and notify the controller.
    func handleEscapeKey() {
        guard isVisible else { return }
        IMELog.info("Esc — suggestion dismissed by user")
        onDismiss?()
        hide()
    }

    /// Move selection down (↓): wraps from last to first.
    func cycleDown() {
        guard isVisible, !edits.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % edits.count
        updateView()
        IMELog.info("↓ selectedIndex=\(selectedIndex)")
    }

    /// Move selection up (↑): wraps from first to last.
    func cycleUp() {
        guard isVisible, !edits.isEmpty else { return }
        selectedIndex = (selectedIndex + edits.count - 1) % edits.count
        updateView()
        IMELog.info("↑ selectedIndex=\(selectedIndex)")
    }

    /// True when the panel is currently on screen.
    var isVisible: Bool { panel != nil }

    // MARK: - Internal helpers

    private func updateView() {
        guard let hv = hostingView else { return }
        hv.rootView = SuggestionView(edits: edits, selectedIndex: selectedIndex)
    }

    // MARK: - Positioning

    private func panelOrigin(caretRect: NSRect,
                             panelSize: NSSize) -> NSPoint {
        // Fall back to main screen centre if the caret rect is degenerate.
        guard caretRect != .zero,
              let screen = screenContaining(caretRect) ?? NSScreen.main else {
            return centreOrigin(panelSize: panelSize)
        }

        let screenFrame = screen.visibleFrame
        let panelH = panelSize.height
        let panelW = panelSize.width

        // Preferred: place the panel just below the caret line.
        var x = caretRect.minX
        var y = caretRect.minY - panelH - Layout.caretGap

        // Flip above if not enough space below.
        if y < screenFrame.minY + Layout.screenMargin {
            y = caretRect.maxY + Layout.caretGap
        }

        // Clamp horizontally within the visible screen.
        let maxX = screenFrame.maxX - panelW - Layout.screenMargin
        let minX = screenFrame.minX + Layout.screenMargin
        x = min(max(x, minX), maxX)

        // Clamp vertically.
        let maxY = screenFrame.maxY - panelH - Layout.screenMargin
        let minY = screenFrame.minY + Layout.screenMargin
        y = min(max(y, minY), maxY)

        return NSPoint(x: x, y: y)
    }

    private func screenContaining(_ rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { NSIntersectionRect($0.frame, rect) != .zero }
    }

    private func centreOrigin(panelSize: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let sf = screen.visibleFrame
        return NSPoint(
            x: sf.midX - panelSize.width / 2,
            y: sf.midY - panelSize.height / 2
        )
    }
}

// MARK: - SuggestionView (SwiftUI)

struct SuggestionView: View {
    let edits: [IMEEdit]
    let selectedIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.2))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(edits.enumerated()), id: \.offset) { idx, edit in
                        EditRow(edit: edit, isSelected: idx == selectedIndex)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 4)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.blue)
            Text("LingoPulse Suggestions")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            Text("\(edits.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

// MARK: - EditRow

private struct EditRow: View {
    let edit: IMEEdit
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                confidenceBadge
                VStack(alignment: .leading, spacing: 3) {
                    textDiff
                    reasonLabel
                }
                Spacer()
                if edit.risk == "risky" {
                    riskPill
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.18)
                      : Color.secondary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(strokeColor, lineWidth: isSelected ? 2.5 : (edit.risk == "risky" ? 1.5 : 0))
        )
    }

    private var strokeColor: Color {
        if isSelected { return Color.accentColor }
        if edit.risk == "risky" { return Color.red }
        return Color.clear
    }

    private var confidenceBadge: some View {
        Group {
            switch edit.confidence {
            case "high":
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            case "medium":
                Image(systemName: "questionmark.circle").foregroundStyle(.orange)
            default:
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
            }
        }
        .font(.system(size: 14))
        .padding(.top, 2)
    }

    private var riskPill: some View {
        Text("REVIEW")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(.red))
    }

    private var textDiff: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(edit.from_text)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary)
                .strikethrough(true, color: .secondary)
                .lineLimit(2)
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(edit.to_text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
        }
    }

    private var reasonLabel: some View {
        Text(edit.reason)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .lineLimit(2)
    }
}
