import AppKit
import SwiftUI
import ApplicationServices

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
    @State private var axGranted: Bool = AXIsProcessTrusted()
    @State private var axPollTimer: Timer? = nil
    @State private var axPollSecondsElapsed: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            stepContent
            Divider()
            navigationBar
        }
        .frame(width: 540, height: 420)
        .onChange(of: step) { _, newStep in
            if newStep == 2 {
                startAXPolling()
            } else {
                stopAXPolling()
            }
        }
        .onDisappear {
            stopAXPolling()
        }
    }

    // MARK: Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:  welcomeStep
        case 1:  installStep
        case 2:  accessibilityStep
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
            Text("LingoPulse corrects your writing as you type — in any app, in any language.\n\nThis quick setup installs the input method and grants the permissions it needs.")
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
            Text("LingoPulse will copy the input method bundle into\n~/Library/Input Methods/ and enable it automatically.")
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

    // Step 2 — Accessibility permission (with scoped AX-grant polling)
    private var accessibilityStep: some View {
        VStack(spacing: 20) {
            Image(systemName: axGranted ? "checkmark.shield.fill" : "hand.raised")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(axGranted ? Color.green : Color.accentColor)
                .animation(.easeInOut(duration: 0.2), value: axGranted)

            Text("Allow Accessibility Access")
                .font(.title.bold())

            if axGranted {
                Text("Accessibility access granted. LingoPulse can now read and correct your text in any app.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 40)
            } else {
                Text("LingoPulse needs Accessibility access to read and correct text.\n\nStep 1: Open System Settings → Privacy & Security → Accessibility. Toggle LingoPulse ON.\nStep 2: Restart LingoPulse so the new permission takes effect (macOS caches this per-process).")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                    .font(.callout)

                HStack(spacing: 10) {
                    Button("Open System Settings") {
                        requestAXAccess()
                    }
                    .buttonStyle(.bordered)

                    Button("I Granted — Restart LingoPulse") {
                        relaunchApp()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 4)
            }
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
                    .disabled(nextDisabled)
            } else {
                Button("Finish") { onComplete() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var nextDisabled: Bool {
        switch step {
        case 1: return installError == nil && !IMEInstaller().isInstalled
        case 2: return !axGranted
        default: return false
        }
    }

    // MARK: Actions

    private func performInstall() {
        installing = true
        installError = nil
        Task { @MainActor in
            defer { installing = false }
            do {
                let installer = IMEInstaller()
                try installer.install()
                let (regStatus, enableStatus) = await installer.enableViaTIS()
                Log.info("TIS register=\(regStatus) enable=\(enableStatus)")
                step += 1
            } catch {
                installError = error.localizedDescription
            }
        }
    }

    /// Prompts the user for AX permission using the scoped
    /// `kAXTrustedCheckOptionPrompt` option.  macOS will open System Settings
    /// → Privacy & Security → Accessibility if the process is not yet trusted.
    private func requestAXAccess() {
        let opts: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: AX polling

    /// Starts a 1-second repeating timer that checks `AXIsProcessTrusted()`.
    /// When the user grants access the timer fires, sets `axGranted = true`,
    /// and auto-advances to the done step.
    private func startAXPolling() {
        guard axPollTimer == nil else { return }
        axGranted = AXIsProcessTrusted()
        axPollSecondsElapsed = 0
        if axGranted {
            step += 1
            return
        }
        axPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                axPollSecondsElapsed += 1
                let trusted = AXIsProcessTrusted()
                if trusted && !axGranted {
                    axGranted = true
                    stopAXPolling()
                    try? await Task.sleep(for: .milliseconds(600))
                    step += 1
                }
            }
        }
    }

    private func stopAXPolling() {
        axPollTimer?.invalidate()
        axPollTimer = nil
    }

    /// Relaunch the app. Required after granting Accessibility because
    /// AXIsProcessTrusted() is cached per-process at launch and won't
    /// reflect the new grant until the process restarts.
    private func relaunchApp() {
        guard let bundlePath = Bundle.main.bundlePath as String? else {
            NSApp.terminate(nil)
            return
        }
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundlePath]
        try? task.run()
        // Give the new instance ~500ms to start, then kill this one
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }
}
