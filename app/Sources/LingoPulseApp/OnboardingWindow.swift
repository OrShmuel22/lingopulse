import AppKit
import SwiftUI

// MARK: - OnboardingWindow

@MainActor
final class OnboardingWindow {
    private var window: NSWindow?

    func show(onComplete: @escaping () -> Void) {
        if window != nil { return }
        let view = OnboardingView(onComplete: { [weak self] in
            self?.close()
            onComplete()
        })
        let hc = NSHostingController(rootView: view)
        hc.view.frame = NSRect(x: 0, y: 0, width: 540, height: 420)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Welcome to LingoPulse"
        win.contentViewController = hc
        win.isReleasedWhenClosed = false
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}

// MARK: - OnboardingView

private struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var step: Int = 0
    @State private var installError: String? = nil
    @State private var installing: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            stepContent
            Divider()
            navigationBar
        }
        .frame(width: 540, height: 420)
    }

    // MARK: Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:  welcomeStep
        case 1:  installStep
        case 2:  activateStep
        case 3:  doneStep
        default: welcomeStep
        }
    }

    // Step 0 — Welcome
    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "character.bubble")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(Color.accentColor)
            Text("Welcome to LingoPulse")
                .font(.largeTitle.bold())
            Text("LingoPulse corrects your writing as you type — in any app, in any language.\n\nThis quick setup installs the input method and adds it to macOS Keyboard settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Step 1 — Install IME
    private var installStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(Color.accentColor)
            Text("Install Input Method")
                .font(.title.bold())
            Text("LingoPulse will copy the input method bundle into\n~/Library/Input Methods/ so macOS can load it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            if let err = installError {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: performInstall) {
                if installing {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 8)
                } else {
                    Text("Install Now")
                        .frame(width: 120)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(installing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Step 2 — Activate in System Settings
    private var activateStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(Color.accentColor)
            Text("Enable in Keyboard Settings")
                .font(.title.bold())
            Text("Open System Settings → Keyboard → Input Sources, then tap \"+\" and add LingoPulse.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            Button("Open Keyboard Settings") {
                openKeyboardSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Step 3 — Done
    private var doneStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(.green)
            Text("You're all set!")
                .font(.largeTitle.bold())
            Text("Switch to LingoPulse in the macOS input menu (top-right of the menu bar) to start typing smarter.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Navigation bar

    private var navigationBar: some View {
        HStack {
            // Step dots
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            Spacer()

            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.bordered)
            }

            if step < 3 {
                Button("Next") { step += 1 }
                    .buttonStyle(.borderedProminent)
                    .disabled(step == 1 && installError == nil && !IMEInstaller().isInstalled)
            } else {
                Button("Finish") { onComplete() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: Actions

    private func performInstall() {
        installing = true
        installError = nil
        Task { @MainActor in
            defer { installing = false }
            do {
                try IMEInstaller().install()
                step += 1
            } catch {
                installError = error.localizedDescription
            }
        }
    }

    private func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?InputSources") {
            NSWorkspace.shared.open(url)
        }
    }
}
