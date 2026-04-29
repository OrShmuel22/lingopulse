import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let host = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: host)
        window.title = "LingoPulse — Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 520))
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
            ModelsPromptsTab(prefs: prefs)
                .tabItem { Label("Models & Prompts", systemImage: "brain") }
            AppsTab(prefs: prefs)
                .tabItem { Label("Apps", systemImage: "app.badge") }
            AdvancedTab(prefs: prefs)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .padding(16)
        .frame(minWidth: 540, minHeight: 480)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Enabled (live suggestions)", isOn: $prefs.enabled)
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
            }
            Section("Triggers") {
                Picker("Single-key trigger", selection: $prefs.triggerSingleKey) {
                    Text("Right ⌘").tag("rightCommand")
                    Text("Right ⌥").tag("rightOption")
                    Text("Fn").tag("fn")
                }
                Picker("Double-tap modifier", selection: $prefs.triggerDoubleTapMod) {
                    Text("Off").tag("off")
                    Text("⇧ Shift").tag("shift")
                    Text("⌘ Command").tag("command")
                    Text("⌥ Option").tag("option")
                }
            }
            Section("Timing") {
                VStack(alignment: .leading) {
                    Text("Debounce: \(String(format: "%.1f", prefs.debounceSeconds))s")
                    Slider(value: $prefs.debounceSeconds, in: 0.5...5.0, step: 0.1)
                }
                VStack(alignment: .leading) {
                    Text("Auto-dismiss: \(String(format: "%.1f", prefs.autoDismissSeconds))s")
                    Slider(value: $prefs.autoDismissSeconds, in: 3.0...15.0, step: 0.5)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Apps (unified)

private struct AppsTab: View {
    @ObservedObject var prefs: Preferences
    @State private var newSuggestionApp: String = ""
    @State private var newLiveApp: String = ""

    var body: some View {
        Form {
            Section("Excluded from live suggestions") {
                Text("Apps in this list never trigger live suggestions.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("App name (e.g. iTerm2)", text: $newSuggestionApp)
                    Button("Add") {
                        let n = newSuggestionApp.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty {
                            prefs.excludedApps.insert(n)
                            newSuggestionApp = ""
                        }
                    }
                }
                if prefs.excludedApps.isEmpty {
                    Text("No apps excluded.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(prefs.excludedApps.sorted(), id: \.self) { name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button("Remove") { prefs.excludedApps.remove(name) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
            Section("Excluded from Live Mode") {
                Text("Live Mode will not fire in these apps. Password managers and terminals are excluded by default.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("App name (e.g. Cursor)", text: $newLiveApp)
                    Button("Add") {
                        let trimmed = newLiveApp.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        prefs.liveModeExcludedApps.insert(trimmed)
                        newLiveApp = ""
                    }
                }
                if prefs.liveModeExcludedApps.isEmpty {
                    Text("No apps excluded.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(prefs.liveModeExcludedApps).sorted(), id: \.self) { name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button("Remove") { prefs.liveModeExcludedApps.remove(name) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced

private struct AdvancedTab: View {
    @ObservedObject var prefs: Preferences
    @State private var showTokenRegenConfirm = false
    @State private var installAlert: AlertInfo? = nil

    var body: some View {
        Form {
            Section("Live Mode") {
                Toggle("Enable Live Mode (experimental)", isOn: $prefs.liveModeEnabled)
                Text("When ON, LingoPulse refines text in any focused field after you pause typing (debounce configurable in General tab). Suggestions appear as a non-intrusive overlay.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Shell Integration (Terminal)") {
                Toggle("Enable shell bridge", isOn: $prefs.shellBridgeEnabled)
                Text("Allows a zsh/bash widget to refine your command-line buffer via a local HTTP server on 127.0.0.1.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Install for zsh") { runInstall(.zsh) }
                    Button("Install for bash") { runInstall(.bash) }
                    Spacer()
                    Button("Token: regenerate") { showTokenRegenConfirm = true }
                        .foregroundStyle(.red)
                }
            }
            Section("Diagnostics") {
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
        .formStyle(.grouped)
        .alert("Regenerate Shell Token?", isPresented: $showTokenRegenConfirm) {
            Button("Regenerate", role: .destructive) { regenerateToken() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes ~/.config/lingopulse/shell-token and restarts the bridge. Any open shell sessions will need to re-source the widget.")
        }
        .alert(item: $installAlert) { info in
            Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")))
        }
    }

    private func runInstall(_ shell: ShellInstaller.Shell) {
        let r = ShellInstaller.install(shell)
        installAlert = AlertInfo(title: r.title, message: r.message)
    }

    private func regenerateToken() {
        ShellInstaller.regenerateToken()
        let wasEnabled = prefs.shellBridgeEnabled
        prefs.shellBridgeEnabled = false
        if wasEnabled {
            prefs.shellBridgeEnabled = true
        }
    }
}

private struct AlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
