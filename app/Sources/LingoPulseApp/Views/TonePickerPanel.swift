import AppKit
import SwiftUI

// Borderless NSPanel that returns true for canBecomeKey so it actually
// receives keyDown events when made key (default borderless windows reject).
private final class KeyableTonePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class TonePickerPanel {
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var globalKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var tones: [String] = []
    private var onPick: ((String) -> Void)?
    private var onCancel: (() -> Void)?
    private var previousApp: NSRunningApplication?
    // Callers use `await TonePickerPanel().show(...)`. show() is non-blocking,
    // so the temporary instance would deallocate immediately and the NSEvent
    // monitors' [weak self] would all become nil — the panel would appear but
    // no keys would be handled. Hold a self reference until dismissal.
    private var selfReference: TonePickerPanel?

    func show(tones: [String], preselected: String, onCancel: (() -> Void)? = nil, onPick: @escaping (String) -> Void) async {
        if panel != nil { return }
        self.tones = tones
        self.onPick = onPick
        self.onCancel = { [weak self] in
            onCancel?()
            self?.close()
        }
        self.previousApp = NSWorkspace.shared.frontmostApplication

        let view = TonePickerView(
            tones: tones,
            preselected: preselected,
            onPick: { [weak self] t in self?.fire(t) },
            onCancel: { [weak self] in self?.close() }
        )

        let hc = NSHostingController(rootView: view)
        hc.view.frame = NSRect(x: 0, y: 0, width: 360, height: 320)

        // Borderless + nonactivating panel matches QuickActionPanel. Local
        // NSEvent monitor delivers keys reliably regardless of SwiftUI focus
        // state, which `.onKeyPress` does not.
        let p = KeyableTonePanel(
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
        self.selfReference = self
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event: event)
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.close() } }
        }
        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        let cancel = onCancel
        onPick = nil
        onCancel = nil
        let prev = previousApp
        previousApp = nil
        prev?.activate()
        cancel?()
        selfReference = nil
    }

    private func fire(_ tone: String) {
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        let cb = onPick
        onPick = nil
        onCancel = nil
        let prev = previousApp
        previousApp = nil
        prev?.activate()
        Task { @MainActor in
            // Wait for source app to regain frontmost status before applying
            // the refine, so accessibility writes hit the right field.
            try? await Task.sleep(for: .milliseconds(120))
            cb?(tone)
        }
        selfReference = nil
    }

    private func removeMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
    }

    private func handleKey(event: NSEvent) -> NSEvent? {
        let chars = event.charactersIgnoringModifiers ?? ""
        if let digit = chars.first.flatMap({ Int(String($0)) }),
           digit >= 1, digit <= min(9, tones.count) {
            fire(tones[digit - 1])
            return nil
        }
        if event.keyCode == 53 { // Escape
            close()
            return nil
        }
        return event
    }
}

private struct TonePickerView: View {
    let tones: [String]
    let preselected: String
    let onPick: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose tone — press number to pick, Esc to cancel")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                VStack(spacing: 0) {
                    ForEach(Array(tones.enumerated()), id: \.element) { idx, tone in
                        ToneRow(
                            index: idx,
                            tone: tone,
                            isPreselected: tone == preselected,
                            onTap: { onPick(tone) }
                        )
                    }
                }
                .padding(6)
                Spacer(minLength: 0)
            }
        }
        .frame(width: 360, height: 320)
    }
}

private struct ToneRow: View {
    let index: Int
    let tone: String
    let isPreselected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text("\(index + 1)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .center)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                    )
                Text(tone)
                    .foregroundStyle(.primary)
                Spacer()
                if isPreselected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
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
