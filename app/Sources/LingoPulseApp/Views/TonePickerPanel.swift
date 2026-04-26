import AppKit
import SwiftUI

@MainActor
final class TonePickerPanel {
    private var window: NSWindow?

    func show(tones: [String], preselected: String, onPick: @escaping (String) -> Void) async {
        if window != nil { return }
        let view = TonePickerView(
            tones: tones,
            preselected: preselected,
            onPick: { [weak self] t in self?.close(); onPick(t) }
        )
        let hc = NSHostingController(rootView: view)
        hc.view.frame = NSRect(x: 0, y: 0, width: 360, height: 280)
        let win = NSPanel(contentRect: hc.view.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Pick Tone"
        win.contentViewController = hc
        win.center()
        win.isFloatingPanel = true
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func close() { window?.orderOut(nil); window = nil }
}

private struct TonePickerView: View {
    let tones: [String]
    let preselected: String
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text("Choose tone for this refinement").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            List(tones, id: \.self) { tone in
                Button(action: { onPick(tone) }) {
                    HStack {
                        Text(tone)
                        Spacer()
                        if tone == preselected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        }
        .padding(.top, 8)
    }
}
