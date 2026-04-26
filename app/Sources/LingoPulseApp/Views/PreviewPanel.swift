import AppKit
import SwiftUI

@MainActor
final class PreviewPanel {
    private var window: NSWindow?

    func show(original: String, refined: String, onAccept: @escaping () -> Void, onReject: @escaping () -> Void) async {
        if window != nil { return }
        let view = PreviewView(
            original: original,
            refined: refined,
            onAccept: { [weak self] in self?.close(); onAccept() },
            onReject: { [weak self] in self?.close(); onReject() }
        )
        let hc = NSHostingController(rootView: view)
        hc.view.frame = NSRect(x: 0, y: 0, width: 560, height: 380)
        let win = NSPanel(contentRect: hc.view.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Preview Refinement"
        win.contentViewController = hc
        win.center()
        win.isFloatingPanel = true
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func close() { window?.orderOut(nil); window = nil }
}

private struct PreviewView: View {
    let original: String
    let refined: String
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Original").font(.caption).foregroundStyle(.secondary)
                ScrollView { Text(original).frame(maxWidth: .infinity, alignment: .leading).padding(8) }
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
                    .frame(maxHeight: 130)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Refined").font(.caption).foregroundStyle(.secondary)
                ScrollView { Text(refined).frame(maxWidth: .infinity, alignment: .leading).padding(8) }
                    .background(Color.green.opacity(0.10))
                    .cornerRadius(6)
                    .frame(maxHeight: 130)
            }
            HStack {
                Spacer()
                Button("Reject") { onReject() }.keyboardShortcut(.escape, modifiers: [])
                Button("Accept") { onAccept() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
