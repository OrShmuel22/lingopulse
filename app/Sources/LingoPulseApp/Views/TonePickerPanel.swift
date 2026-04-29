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
            onPick: { [weak self] t in self?.close(); onPick(t) },
            onCancel: { [weak self] in self?.close() }
        )
        let hc = NSHostingController(rootView: view)
        hc.view.frame = NSRect(x: 0, y: 0, width: 360, height: 320)
        let win = NSPanel(contentRect: hc.view.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Pick Tone"
        win.contentViewController = hc
        win.center()
        win.isFloatingPanel = true
        win.becomesKeyOnlyIfNeeded = false
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
    let onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Choose tone — press number to pick, Esc to cancel")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal)
            List {
                ForEach(Array(tones.enumerated()), id: \.element) { idx, tone in
                    Button(action: { onPick(tone) }) {
                        HStack {
                            if idx < 9 {
                                Text("\(idx + 1)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, alignment: .leading)
                            } else {
                                Text(" ").frame(width: 18)
                            }
                            Text(tone)
                            Spacer()
                            if tone == preselected {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.top, 8)
        .focusable()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress { press in
            if press.key == .escape {
                onCancel()
                return .handled
            }
            if let scalar = press.characters.unicodeScalars.first,
               let digit = Int(String(scalar)),
               digit >= 1, digit <= min(9, tones.count) {
                onPick(tones[digit - 1])
                return .handled
            }
            return .ignored
        }
    }
}
