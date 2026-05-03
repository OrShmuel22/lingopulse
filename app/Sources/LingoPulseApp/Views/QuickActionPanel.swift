import AppKit
import SwiftUI

enum QuickAction: Int, CaseIterable, Identifiable {
    case quickRefine = 1, refine, preview, tone, undo
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .refine:      return "Refine"
        case .preview:     return "Preview"
        case .tone:        return "Tone"
        case .quickRefine: return "Quick Refine"
        case .undo:        return "Undo"
        }
    }

    var systemImage: String {
        switch self {
        case .refine:      return "wand.and.stars"
        case .preview:     return "eye"
        case .tone:        return "paintpalette.fill"
        case .quickRefine: return "square.and.pencil"
        case .undo:        return "arrow.uturn.backward"
        }
    }

    var shortcutHint: String { String(rawValue) }
}

// Borderless NSPanel that returns true for canBecomeKey so it actually
// receives keyDown events when made key (default borderless windows reject).
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickActionPanel {
    private var panel: NSPanel?
    private var monitor: Any?
    private var globalKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var callback: ((QuickAction?) -> Void)?
    private var previousApp: NSRunningApplication?

    init() {}

    func show(anchor: AXUIElement?, onPick: @escaping (QuickAction?) -> Void) {
        if panel != nil { close() }
        callback = onPick
        previousApp = NSWorkspace.shared.frontmostApplication

        let vm = QuickActionPanelViewModel()
        let view = QuickActionView(vm: vm, onSelect: { [weak self] action in
            self?.fire(action)
        })

        let hc = NSHostingController(rootView: view)
        hc.view.frame = NSRect(x: 0, y: 0, width: 240, height: 240)

        let p = KeyablePanel(
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

        let origin = panelOrigin(anchor: anchor, size: hc.view.frame.size)
        p.setFrameOrigin(origin)

        self.panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event: event, vm: vm)
        }
        // Global Esc dismisses the panel even when the source app keeps focus
        // (local monitor only fires when this app is key).
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.close() } }
        }
        // Click anywhere outside the panel = dismiss.
        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    func close() {
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        let cb = callback
        callback = nil
        let prev = previousApp
        previousApp = nil
        prev?.activate()
        cb?(nil)
    }

    private func fire(_ action: QuickAction) {
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        let cb = callback
        callback = nil
        let prev = previousApp
        previousApp = nil
        prev?.activate()
        Task { @MainActor in
            // Wait for source app to actually regain frontmost status before
            // running the action. Without this, refine/preview/etc. read
            // selection from this app instead of the source field.
            try? await Task.sleep(for: .milliseconds(120))
            cb?(action)
        }
    }

    private func removeMonitors() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
    }

    private func handleKey(event: NSEvent, vm: QuickActionPanelViewModel) -> NSEvent? {
        let chars = event.charactersIgnoringModifiers ?? ""
        if let digit = chars.first.flatMap({ Int(String($0)) }),
           digit >= 1 && digit <= 5,
           let action = QuickAction(rawValue: digit) {
            fire(action)
            return nil
        }
        switch event.keyCode {
        case 125: vm.moveDown(); return nil
        case 126: vm.moveUp(); return nil
        case 36:
            fire(vm.highlighted)
            return nil
        case 53:
            close()
            return nil
        default: return event
        }
    }

    private func panelOrigin(anchor: AXUIElement?, size: CGSize) -> CGPoint {
        let caretRect: CGRect?
        if let el = anchor {
            caretRect = CaretLocator.locate(in: el)
        } else {
            caretRect = nil
        }

        if let rect = caretRect {
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let screenFrame = screen.frame
            var x = rect.minX
            var y = rect.minY - size.height - 4
            if y < screenFrame.minY { y = rect.maxY + 4 }
            if x + size.width > screenFrame.maxX { x = screenFrame.maxX - size.width }
            if x < screenFrame.minX { x = screenFrame.minX }
            return CGPoint(x: x, y: y)
        }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.frame
        return CGPoint(
            x: sf.midX - size.width / 2,
            y: sf.midY - size.height / 2
        )
    }
}

@MainActor
final class QuickActionPanelViewModel: ObservableObject {
    @Published var highlightedIndex: Int = 0

    var highlighted: QuickAction { QuickAction.allCases[highlightedIndex] }

    func moveDown() {
        highlightedIndex = (highlightedIndex + 1) % QuickAction.allCases.count
    }

    func moveUp() {
        highlightedIndex = (highlightedIndex - 1 + QuickAction.allCases.count) % QuickAction.allCases.count
    }
}

private struct QuickActionView: View {
    @ObservedObject var vm: QuickActionPanelViewModel
    let onSelect: (QuickAction) -> Void

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(spacing: 0) {
                ForEach(Array(QuickAction.allCases.enumerated()), id: \.element.id) { idx, action in
                    ActionRow(
                        action: action,
                        isHighlighted: idx == vm.highlightedIndex,
                        onTap: { onSelect(action) }
                    )
                    .onHover { inside in
                        if inside { vm.highlightedIndex = idx }
                    }
                }
            }
            .padding(6)
        }
        .frame(width: 240, height: 240)
    }
}

private struct ActionRow: View {
    let action: QuickAction
    let isHighlighted: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: action.systemImage)
                    .frame(width: 20)
                    .foregroundStyle(isHighlighted ? .white : .primary)
                Text(action.label)
                    .foregroundStyle(isHighlighted ? .white : .primary)
                Spacer()
                Text(action.shortcutHint)
                    .font(.caption.monospaced())
                    .foregroundStyle(isHighlighted ? .white.opacity(0.7) : .secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isHighlighted ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15))
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHighlighted ? Color.accentColor : Color.clear)
            )
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
