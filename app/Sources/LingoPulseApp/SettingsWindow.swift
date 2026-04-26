import AppKit
import SwiftUI
import Carbon.HIToolbox

final class SettingsWindowController: NSWindowController {
    convenience init(daemon: DaemonClient) {
        let host = NSHostingController(rootView: SettingsView(daemon: daemon))
        let window = NSWindow(contentViewController: host)
        window.title = "LingoPulse — Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 540, height: 460))
        window.center()
        self.init(window: window)
    }
}

struct SettingsView: View {
    let daemon: DaemonClient
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        TabView {
            GeneralTab(prefs: prefs, daemon: daemon)
                .tabItem { Label("General", systemImage: "gearshape") }
            HotkeyTab(prefs: prefs)
                .tabItem { Label("Hotkey", systemImage: "keyboard") }
            AppsTab(prefs: prefs)
                .tabItem { Label("Apps", systemImage: "app.badge") }
            AdvancedTab(prefs: prefs)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct GeneralTab: View {
    @ObservedObject var prefs: Preferences
    let daemon: DaemonClient
    @State private var statusMessage: String = ""

    var body: some View {
        Form {
            Toggle("Enabled (live suggestions)", isOn: $prefs.enabled)
            Toggle("Launch at login", isOn: $prefs.launchAtLogin)
            HStack {
                TextField("Daemon URL", text: $prefs.daemonURL)
                Button("Test") {
                    Task { await test() }
                }
            }
            if !statusMessage.isEmpty {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func test() async {
        do {
            let s = try await daemon.status()
            statusMessage = "OK · model=\(s.model) loaded=\(s.model_loaded)"
        } catch {
            statusMessage = "Failed: \(error)"
        }
    }
}

private struct HotkeyTab: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            HStack {
                Text("Manual refine hotkey:")
                HotkeyCaptureField(
                    keyCode: $prefs.hotkeyKeyCode,
                    modifiers: $prefs.hotkeyModifiers
                )
                .frame(minWidth: 160)
            }
            Text("Click the field, press a key combination. Default: ⌘⌥G.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct HotkeyCaptureField: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: UInt32

    func makeNSView(context: Context) -> HotkeyCaptureNSView {
        let v = HotkeyCaptureNSView()
        v.onCapture = { kc, mods in
            keyCode = kc
            modifiers = mods
        }
        v.update(keyCode: keyCode, modifiers: modifiers)
        return v
    }

    func updateNSView(_ nsView: HotkeyCaptureNSView, context: Context) {
        nsView.update(keyCode: keyCode, modifiers: modifiers)
    }
}

final class HotkeyCaptureNSView: NSView {
    private let label = NSTextField(labelWithString: "")
    var onCapture: ((Int, UInt32) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 4

        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        layer?.borderColor = NSColor.systemBlue.cgColor
        return super.becomeFirstResponder()
    }
    override func resignFirstResponder() -> Bool {
        layer?.borderColor = NSColor.separatorColor.cgColor
        return super.resignFirstResponder()
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbonMods: UInt32 = 0
        if mods.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if mods.contains(.option) { carbonMods |= UInt32(optionKey) }
        if mods.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if mods.contains(.control) { carbonMods |= UInt32(controlKey) }
        if carbonMods != 0 {
            onCapture?(Int(event.keyCode), carbonMods)
        }
    }

    func update(keyCode: Int, modifiers: UInt32) {
        var s = ""
        if (modifiers & UInt32(cmdKey)) != 0 { s += "⌘" }
        if (modifiers & UInt32(optionKey)) != 0 { s += "⌥" }
        if (modifiers & UInt32(shiftKey)) != 0 { s += "⇧" }
        if (modifiers & UInt32(controlKey)) != 0 { s += "⌃" }
        s += keyCodeToString(keyCode)
        label.stringValue = s
    }

    private func keyCodeToString(_ kc: Int) -> String {
        let map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab",
        ]
        return map[kc] ?? "[\(kc)]"
    }
}

private struct AppsTab: View {
    @ObservedObject var prefs: Preferences
    @State private var newAppName: String = ""

    var body: some View {
        Form {
            Text("Apps in this list never trigger live suggestions.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("App name (e.g. iTerm2)", text: $newAppName)
                Button("Add") {
                    let n = newAppName.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty {
                        prefs.excludedApps.insert(n)
                        newAppName = ""
                    }
                }
            }
            List {
                ForEach(prefs.excludedApps.sorted(), id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button("Remove") { prefs.excludedApps.remove(name) }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 200)
        }
    }
}

private struct AdvancedTab: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            VStack(alignment: .leading) {
                Text("Debounce: \(String(format: "%.1f", prefs.debounceSeconds))s")
                Slider(value: $prefs.debounceSeconds, in: 0.5...5.0, step: 0.1)
            }
            VStack(alignment: .leading) {
                Text("Auto-dismiss: \(String(format: "%.1f", prefs.autoDismissSeconds))s")
                Slider(value: $prefs.autoDismissSeconds, in: 3.0...15.0, step: 0.5)
            }
            Picker("Log level", selection: $prefs.logLevel) {
                Text("Off").tag("Off")
                Text("Basic").tag("Basic")
                Text("Verbose").tag("Verbose")
            }
            HStack {
                Button("Reset Accessibility permission") {
                    let task = Process()
                    task.launchPath = "/usr/bin/tccutil"
                    task.arguments = ["reset", "Accessibility", "com.lingopulse.app"]
                    try? task.run()
                }
                Spacer()
            }
        }
    }
}
