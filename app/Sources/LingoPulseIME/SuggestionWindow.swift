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
///   first.  Tab / Escape handling is logged here as a stub for Phase 6.
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
    }

    // MARK: - Internals

    private var panel: NSPanel?
    private var dismissTask: DispatchWorkItem?

    // MARK: - Public API

    /// Show suggestions near the given caret rectangle (screen coordinates).
    /// If `caretScreenRect` is `.zero` the panel falls back to screen centre.
    func show(edits: [IMEEdit], caretScreenRect: NSRect) {
        hide() // dismiss any previous panel before creating a new one

        guard !edits.isEmpty else { return }

        let content = SuggestionView(edits: edits)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0,
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
        newPanel.contentView = hostingView
        newPanel.ignoresMouseEvents = false // allow future click-accept in Phase 6

        let origin = panelOrigin(caretRect: caretScreenRect,
                                 panelSize: NSSize(width: Layout.panelWidth,
                                                   height: Layout.panelMaxHeight))
        newPanel.setFrameOrigin(origin)
        newPanel.orderFront(nil)

        panel = newPanel

        // Schedule auto-dismiss
        let task = DispatchWorkItem { [weak self] in self?.hide() }
        dismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.autoDismiss,
                                      execute: task)

        NSLog("LingoPulseIME: SuggestionWindow shown (\(edits.count) edit(s)) at \(origin)")
    }

    /// Hide and tear down the panel immediately.
    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Tab / Escape stubs (Phase 6)

    /// Called by the controller's didCommand handler when Tab is pressed
    /// while the suggestion panel is visible.  Accepting the suggestion is
    /// implemented in Phase 6; for now we log and dismiss.
    func handleTabKey() {
        NSLog("LingoPulseIME: user pressed Tab — suggestion accept stub (Phase 6)")
        hide()
    }

    /// Called when Escape is pressed while the panel is visible.
    func handleEscapeKey() {
        NSLog("LingoPulseIME: user pressed Esc — suggestion dismissed")
        hide()
    }

    /// True when the panel is currently on screen.
    var isVisible: Bool { panel != nil }

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

private struct SuggestionView: View {
    let edits: [IMEEdit]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.2))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(edits.enumerated()), id: \.offset) { _, edit in
                        EditRow(edit: edit)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                confidenceDot
                VStack(alignment: .leading, spacing: 3) {
                    textDiff
                    reasonLabel
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.07))
        )
    }

    private var confidenceDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .padding(.top, 4)
    }

    private var dotColor: Color {
        switch edit.confidence {
        case "high":   return .green
        case "medium": return .orange
        default:       return .red
        }
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
