import AppKit
import SwiftUI

private final class KeyableCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickRefineCapturePanel {
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var globalKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var onPick: ((String?) -> Void)?
    private var previousApp: NSRunningApplication?
    private var selfReference: QuickRefineCapturePanel?
    private var textBinding: TextBinding?

    func show(onPick: @escaping (String?) -> Void) {
        if panel != nil { return }
        self.onPick = onPick
        self.previousApp = NSWorkspace.shared.frontmostApplication

        let binding = TextBinding()
        self.textBinding = binding

        let view = QuickRefineCaptureView(
            binding: binding,
            onSubmit: { [weak self] in self?.fire() },
            onCancel: { [weak self] in self?.cancel() }
        )

        let hc = NSHostingController(rootView: view)
        hc.view.frame = NSRect(x: 0, y: 0, width: 520, height: 220)

        let p = KeyableCapturePanel(
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
    }

    func close() {
        cancel()
    }

    private func cancel() {
        guard panel != nil else { return }
        teardown()
        let cb = onPick
        onPick = nil
        cb?(nil)
        selfReference = nil
    }

    private func fire() {
        let text = (textBinding?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        teardown()
        let cb = onPick
        onPick = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            cb?(text.isEmpty ? nil : text)
        }
        selfReference = nil
    }

    private func teardown() {
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        textBinding = nil
        let prev = previousApp
        previousApp = nil
        prev?.activate()
    }

    private func removeMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
    }
}

@MainActor
final class TextBinding: ObservableObject {
    @Published var text: String = ""
}

private struct QuickRefineCaptureView: View {
    @ObservedObject var binding: TextBinding
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Refine — type or paste text")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $binding.text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.10))
                    )
                HStack(spacing: 12) {
                    ShortcutHint(key: "↩", label: "Refine")
                    ShortcutHint(key: "⇧↩", label: "Newline")
                    Spacer()
                    ShortcutHint(key: "Esc", label: "Cancel")
                }
                .font(.caption)
            }
            .padding(14)
        }
        .frame(width: 520, height: 220)
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
