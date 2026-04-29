import AppKit
import SwiftUI

private final class KeyablePreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PreviewPanel {
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var globalKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var onAccept: (() -> Void)?
    private var onReject: (() -> Void)?
    private var refinedText: String = ""
    private var previousApp: NSRunningApplication?
    private var hasFiredCallback = false

    /// `axWriteAvailable=false` means the source field is in an app that does
    /// not expose AX text writing (terminals, Claude Code, etc.). In that case
    /// the panel pre-copies the refined text to the clipboard on open and shows
    /// a "Refined copied — press Esc to paste" banner so Esc-only flow works.
    func show(
        original: String,
        refined: String,
        axWriteAvailable: Bool,
        onAccept: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) async {
        if panel != nil { return }
        self.onAccept = onAccept
        self.onReject = onReject
        self.refinedText = refined
        self.previousApp = NSWorkspace.shared.frontmostApplication
        self.hasFiredCallback = false

        // Auto-copy when the source app can't accept an AX write. The user's
        // entire flow becomes shift-shift → 1 → Esc → ⌘V.
        if !axWriteAvailable {
            ClipboardService.copy(refined)
        }

        let view = PreviewView(
            original: original,
            refined: refined,
            axWriteAvailable: axWriteAvailable,
            onAccept: { [weak self] in self?.fireAccept() },
            onCopy: { [weak self] in self?.fireCopy() },
            onReject: { [weak self] in self?.fireReject() }
        )

        let hc = NSHostingController(rootView: view)
        hc.view.frame = NSRect(x: 0, y: 0, width: 620, height: 460)

        let p = KeyablePreviewPanel(
            contentRect: hc.view.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentViewController = hc
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.center()

        self.panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event: event)
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.fireReject() } }
        }
        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self] _ in
            // Outside-click counts as reject so the ring entry rolls back.
            Task { @MainActor in self?.fireReject() }
        }
    }

    private func fireAccept() { fire { self.onAccept?() } }
    private func fireReject() { fire { self.onReject?() } }
    private func fireCopy() {
        // C is a non-destructive exit — copy refined, dismiss, leave ring entry.
        ClipboardService.copy(refinedText)
        fire { /* neither accept nor reject */ }
    }

    private func fire(_ callback: @escaping () -> Void) {
        if hasFiredCallback { return }
        hasFiredCallback = true
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        let prev = previousApp
        previousApp = nil
        prev?.activate()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            callback()
        }
        // Drop callbacks after firing to avoid double-call.
        onAccept = nil
        onReject = nil
    }

    private func removeMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
    }

    private func handleKey(event: NSEvent) -> NSEvent? {
        let chars = (event.charactersIgnoringModifiers ?? "").lowercased()
        switch event.keyCode {
        case 36, 76: // Return / numpad Enter
            fireAccept()
            return nil
        case 53: // Escape
            fireReject()
            return nil
        default:
            break
        }
        switch chars {
        case "c":
            fireCopy()
            return nil
        case "d":
            // Diff toggle is a SwiftUI @State inside the view; rebroadcast a
            // notification the view listens for.
            NotificationCenter.default.post(name: .lpPreviewToggleDiff, object: nil)
            return nil
        default:
            return event
        }
    }
}

extension Notification.Name {
    static let lpPreviewToggleDiff = Notification.Name("lp.preview.toggleDiff")
}

// MARK: - Word diff

/// Word-level diff over whitespace-separated tokens. LCS-based; sufficient for
/// the typical refine size (a few hundred chars). Returns a flat token list
/// where each token is tagged same / removed / added; whitespace is preserved
/// as part of the same-side tokens to keep render layout natural.
enum PreviewDiff {
    enum Kind { case same, removed, added }
    struct Segment: Equatable { let kind: Kind; let text: String }

    static func compute(original: String, refined: String) -> [Segment] {
        let a = tokenize(original)
        let b = tokenize(refined)
        if a == b { return [Segment(kind: .same, text: refined)] }

        // Standard LCS table (rows: a, cols: b).
        let m = a.count, n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0..<m {
            for j in 0..<n {
                if a[i] == b[j] {
                    dp[i + 1][j + 1] = dp[i][j] + 1
                } else {
                    dp[i + 1][j + 1] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        var segs: [Segment] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && a[i - 1] == b[j - 1] {
                segs.append(Segment(kind: .same, text: a[i - 1]))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                segs.append(Segment(kind: .added, text: b[j - 1]))
                j -= 1
            } else {
                segs.append(Segment(kind: .removed, text: a[i - 1]))
                i -= 1
            }
        }
        return segs.reversed()
    }

    /// Splits on whitespace boundaries, keeping the whitespace as its own tokens
    /// so re-rendering preserves the original spacing.
    private static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsWS: Bool? = nil
        for ch in s {
            let isWS = ch.isWhitespace
            if currentIsWS == nil { currentIsWS = isWS }
            if isWS == currentIsWS { current.append(ch) }
            else {
                if !current.isEmpty { tokens.append(current) }
                current = String(ch)
                currentIsWS = isWS
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}

// MARK: - View

private struct PreviewView: View {
    let original: String
    let refined: String
    let axWriteAvailable: Bool
    let onAccept: () -> Void
    let onCopy: () -> Void
    let onReject: () -> Void

    @State private var showDiff: Bool = false

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 10) {
                if !axWriteAvailable {
                    BannerView(text: "Refined copied to clipboard — press Esc to dismiss, then ⌘V in your app.")
                }

                if showDiff {
                    DiffSection(original: original, refined: refined)
                } else {
                    SideBySideSection(original: original, refined: refined)
                }

                FooterView(axWriteAvailable: axWriteAvailable,
                           showDiff: showDiff,
                           onAccept: onAccept,
                           onCopy: onCopy,
                           onReject: onReject,
                           onToggleDiff: { showDiff.toggle() })
            }
            .padding(14)
        }
        .frame(width: 620, height: 460)
        .onReceive(NotificationCenter.default.publisher(for: .lpPreviewToggleDiff)) { _ in
            showDiff.toggle()
        }
    }
}

private struct BannerView: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.12))
        )
    }
}

private struct SideBySideSection: View {
    let original: String
    let refined: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Original").font(.caption).foregroundStyle(.secondary)
                ScrollView { Text(original).frame(maxWidth: .infinity, alignment: .leading).padding(8) }
                    .background(Color.secondary.opacity(0.10))
                    .cornerRadius(6)
                    .frame(maxHeight: 130)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Refined").font(.caption).foregroundStyle(.secondary)
                ScrollView { Text(refined).frame(maxWidth: .infinity, alignment: .leading).padding(8) }
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(6)
                    .frame(maxHeight: 200)
            }
        }
    }
}

private struct DiffSection: View {
    let original: String
    let refined: String

    private var attributed: AttributedString {
        var out = AttributedString()
        for seg in PreviewDiff.compute(original: original, refined: refined) {
            var piece = AttributedString(seg.text)
            switch seg.kind {
            case .same:
                piece.foregroundColor = .primary
            case .removed:
                piece.foregroundColor = Color(nsColor: .systemRed)
                piece.backgroundColor = Color.red.opacity(0.12)
                piece.strikethroughStyle = .single
            case .added:
                piece.foregroundColor = Color(nsColor: .systemGreen)
                piece.backgroundColor = Color.green.opacity(0.18)
            }
            out.append(piece)
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Diff").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                Text(attributed)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(6)
            .frame(maxHeight: 340)
        }
    }
}

private struct FooterView: View {
    let axWriteAvailable: Bool
    let showDiff: Bool
    let onAccept: () -> Void
    let onCopy: () -> Void
    let onReject: () -> Void
    let onToggleDiff: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ShortcutHint(key: "Enter", label: axWriteAvailable ? "Apply" : "Apply (paste)")
            ShortcutHint(key: "C", label: "Copy")
            ShortcutHint(key: "D", label: showDiff ? "Hide diff" : "Show diff")
            Spacer()
            ShortcutHint(key: "Esc", label: "Reject")

            Button("Reject", action: onReject).buttonStyle(.bordered)
            Button("Copy", action: onCopy).buttonStyle(.bordered)
            Button("Diff", action: onToggleDiff).buttonStyle(.bordered)
            Button("Apply", action: onAccept).buttonStyle(.borderedProminent)
        }
    }
}

private struct ShortcutHint: View {
    let key: String
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption.monospaced())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.18))
                )
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .menu
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
