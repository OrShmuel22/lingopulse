import AppKit
import KeyboardShortcuts
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let host = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: host)
        window.title = "LingoPulse — Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 540, height: 460))
        window.center()
        self.init(window: window)
    }
}

struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        TabView {
            GeneralTab(prefs: prefs)
                .tabItem { Label("General", systemImage: "gearshape") }
            HotkeyTab()
                .tabItem { Label("Hotkeys", systemImage: "command") }
            AppsTab(prefs: prefs)
                .tabItem { Label("Apps", systemImage: "app.badge") }
            AdvancedTab(prefs: prefs)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            LiveModeTab(prefs: prefs)
                .tabItem { Label("Live Mode", systemImage: "wand.and.stars") }
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

    var body: some View {
        Form {
            Toggle("Enabled (live suggestions)", isOn: $prefs.enabled)
            Toggle("Launch at login", isOn: $prefs.launchAtLogin)
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

private struct LiveModeTab: View {
    @ObservedObject var prefs: Preferences
    @State private var newApp: String = ""

    var body: some View {
        Form {
            Section("Live Refinement") {
                Toggle("Enable Live Mode (experimental)", isOn: $prefs.liveModeEnabled)
                Text("When ON, LingoPulse refines text in any focused field after you pause typing for 800ms. Suggestions appear as a non-intrusive overlay.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Excluded Apps") {
                Text("Live Mode will not fire in these apps. Password managers and terminals are excluded by default.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(prefs.liveModeExcludedApps).sorted(), id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button("Remove") {
                            prefs.liveModeExcludedApps.remove(name)
                        }
                    }
                }
                HStack {
                    TextField("Add app name (e.g. Cursor)", text: $newApp)
                    Button("Add") {
                        let trimmed = newApp.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        prefs.liveModeExcludedApps.insert(trimmed)
                        newApp = ""
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480)
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
