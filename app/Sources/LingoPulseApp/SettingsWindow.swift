import AppKit
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
            TriggersTab(prefs: prefs)
                .tabItem { Label("Triggers", systemImage: "command") }
            AppsTab(prefs: prefs)
                .tabItem { Label("Apps", systemImage: "app.badge") }
            AdvancedTab(prefs: prefs)
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
            ModelsPromptsTab(prefs: prefs)
                .tabItem { Label("Models & Prompts", systemImage: "brain") }
            LiveModeTab(prefs: prefs)
                .tabItem { Label("Live Mode", systemImage: "wand.and.stars") }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct TriggersTab: View {
    @ObservedObject var prefs: Preferences
    @State private var showTokenRegenConfirm = false
    @State private var installAlert: AlertInfo? = nil

    var body: some View {
        Form {
            Section("Trigger Keys") {
                Picker("Single-key trigger", selection: $prefs.triggerSingleKey) {
                    Text("Right ⌘").tag("rightCommand")
                    Text("Right ⌥").tag("rightOption")
                    Text("Fn").tag("fn")
                }
                Picker("Double-tap modifier", selection: $prefs.triggerDoubleTapMod) {
                    Text("⇧ Shift").tag("shift")
                    Text("⌘ Command").tag("command")
                    Text("⌥ Option").tag("option")
                }
            }
            Section("Shell Integration (Terminal)") {
                Toggle("Enable shell bridge", isOn: $prefs.shellBridgeEnabled)
                Text("Allows a zsh/bash widget to refine your command-line buffer via a local HTTP server on 127.0.0.1.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Install for zsh") { installShell(shell: .zsh) }
                    Button("Install for bash") { installShell(shell: .bash) }
                    Spacer()
                    Button("Token: regenerate") { showTokenRegenConfirm = true }
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480)
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

    private enum Shell { case zsh, bash }

    private func installShell(shell: Shell) {
        let scriptName: String
        let rcFile: String
        let bindLine: String
        let sourceLine: String

        switch shell {
        case .zsh:
            scriptName = "lp-refine.zsh"
            rcFile = (ProcessInfo.processInfo.environment["ZDOTDIR"] ?? NSHomeDirectory()) + "/.zshrc"
            sourceLine = "source \"${HOME}/.config/lingopulse/lp-refine.zsh\""
            bindLine = "bindkey '^G' lp-refine"
        case .bash:
            scriptName = "lp-refine.bash"
            rcFile = NSHomeDirectory() + "/.bashrc"
            sourceLine = "source \"${HOME}/.config/lingopulse/lp-refine.bash\""
            bindLine = "bind -x '\"\\C-g\": lp-refine'"
        }

        // Locate bundled script
        let ext = (scriptName as NSString).pathExtension
        let base = (scriptName as NSString).deletingPathExtension
        guard let bundledURL = Bundle.main.url(forResource: base, withExtension: ext) else {
            installAlert = AlertInfo(title: "Script not found",
                message: "\(scriptName) is not bundled in the app. Rebuild with build-bundle.sh.")
            return
        }

        // Install to ~/.config/lingopulse/
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/lingopulse")
        let destURL = configDir.appendingPathComponent(scriptName)
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: bundledURL, to: destURL)
        } catch {
            installAlert = AlertInfo(title: "Install failed", message: error.localizedDescription)
            return
        }

        // Append to rc file idempotently
        let rcURL = URL(fileURLWithPath: rcFile)
        do {
            let existing = (try? String(contentsOf: rcURL, encoding: .utf8)) ?? ""
            var appended = ""
            // LingoPulse block header used for idempotency check on source line
            if !existing.contains("lp-refine.\(ext == "zsh" ? "zsh" : "bash")") {
                appended += "\n# LingoPulse shell integration\n\(sourceLine)\n"
            }
            if !existing.contains(bindLine) {
                appended += "\(bindLine)\n"
            }
            if !appended.isEmpty {
                guard let data = appended.data(using: .utf8) else { throw CocoaError(.fileWriteUnknown) }
                let handle = try FileHandle(forWritingTo: rcURL)
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } catch {
            // rc file may not exist yet — create it
            do {
                let content = "# LingoPulse shell integration\n\(sourceLine)\n\(bindLine)\n"
                try content.write(to: rcURL, atomically: true, encoding: .utf8)
            } catch let writeError {
                installAlert = AlertInfo(title: "Could not write \(rcFile)", message: writeError.localizedDescription)
                return
            }
        }

        installAlert = AlertInfo(
            title: "Installed",
            message: "Added to \(rcFile). Open a new terminal or run `source \(rcFile)`."
        )
    }

    private func regenerateToken() {
        let tokenFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/lingopulse/shell-token")
        try? FileManager.default.removeItem(at: tokenFile)
        // Toggle bridge off then on to pick up the fresh token
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
