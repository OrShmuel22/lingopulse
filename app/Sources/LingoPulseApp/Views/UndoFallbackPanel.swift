import AppKit
import SwiftUI

@MainActor
final class UndoFallbackPanel {
    private var window: NSWindow?

    func show(entries: [[String: Any]], onPick: @escaping ([String: Any]) -> Void) async {
        if window != nil { return }
        let view = UndoListView(entries: entries.prefix(5).map { $0 }, onPick: { [weak self] e in
            self?.close()
            onPick(e)
        })
        let hc = NSHostingController(rootView: view)
        hc.view.frame = NSRect(x: 0, y: 0, width: 460, height: 320)
        let win = NSPanel(
            contentRect: hc.view.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Undo — Recent Refinements"
        win.contentViewController = hc
        win.center()
        win.isFloatingPanel = true
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
    }
}

private struct UndoListView: View {
    let entries: [[String: Any]]
    let onPick: ([String: Any]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(0..<entries.count, id: \.self) { i in
                let e = entries[i]
                let refined = (e["refined"] as? String ?? "").prefix(80)
                let app = e["app"] as? String ?? "?"
                HStack {
                    VStack(alignment: .leading) {
                        Text(refined).font(.body)
                        Text(app).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restore") { onPick(e) }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
