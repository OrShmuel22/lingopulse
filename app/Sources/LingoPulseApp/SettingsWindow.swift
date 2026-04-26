import AppKit
import KeyboardShortcuts
import SwiftUI

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
            HotkeyTab()
                .tabItem { Label("Hotkeys", systemImage: "command") }
            AppsTab(prefs: prefs)
                .tabItem { Label("Apps", systemImage: "app.badge") }
            AdvancedTab(prefs: prefs)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct HotkeyTab: View {
    var body: some View {
        Form {
            Section("Commands") {
                LabeledContent("Refine Selection") {
                    KeyboardShortcuts.Recorder(for: .refine)
                }
                LabeledContent("Refine (Preview)") {
                    KeyboardShortcuts.Recorder(for: .preview)
                }
                LabeledContent("Undo Last Refinement") {
                    KeyboardShortcuts.Recorder(for: .undo)
                }
                LabeledContent("Refine with Tone") {
                    KeyboardShortcuts.Recorder(for: .tone)
                }
                LabeledContent("Find a Word (Dictionary)") {
                    KeyboardShortcuts.Recorder(for: .dictionary)
                }
                LabeledContent("Save as Style Example") {
                    KeyboardShortcuts.Recorder(for: .captureStyle)
                }
            }
            Section {
                Button("Reset to Defaults") {
                    KeyboardShortcuts.reset(.refine, .preview, .undo, .tone, .dictionary, .captureStyle)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480)
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
