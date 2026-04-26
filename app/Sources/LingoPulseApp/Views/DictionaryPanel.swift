import AppKit
import SwiftUI

@MainActor
final class DictionaryPanel {
    private var window: NSWindow?

    func show(query: String, candidates: [DictionaryCandidate]) async {
        if window != nil { return }
        let view = DictionaryView(query: query, candidates: candidates, onPick: { [weak self] cand in
            ClipboardService.copy(cand.word)
            self?.close()
        })
        let hc = NSHostingController(rootView: view)
        hc.view.frame = NSRect(x: 0, y: 0, width: 480, height: 360)
        let win = NSPanel(contentRect: hc.view.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Dictionary — \(query.prefix(40))"
        win.contentViewController = hc
        win.center()
        win.isFloatingPanel = true
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func close() { window?.orderOut(nil); window = nil }
}

private struct DictionaryView: View {
    let query: String
    let candidates: [DictionaryCandidate]
    let onPick: (DictionaryCandidate) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text("Pick a word — copies to clipboard").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            List(0..<candidates.count, id: \.self) { i in
                let c = candidates[i]
                Button(action: { onPick(c) }) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(c.word).font(.title3).bold()
                            Text(c.register).font(.caption).foregroundStyle(.secondary)
                            if c.confidence == "low" {
                                Text("⚠️ low").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        if !c.example.isEmpty {
                            Text(c.example).font(.callout).foregroundStyle(.secondary).italic()
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
            }
        }
        .padding(.top, 8)
    }
}
