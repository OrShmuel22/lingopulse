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
    @State private var axGranted: Bool = AXIsProcessTrusted()
    @State private var axPollTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            stepContent
            Divider()
            navigationBar
        }
        .frame(width: 540, height: 420)
        .onChange(of: step) { _, newStep in
            if newStep == 1 {
                startAXPolling()
            } else {
                stopAXPolling()
            }
        }
        .onDisappear {
            stopAXPolling()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:  welcomeStep
        case 1:  accessibilityStep
        default: welcomeStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "character.bubble")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(Color.accentColor)
            Text("Welcome to LingoPulse")
                .font(.largeTitle.bold())
            Text("LingoPulse refines your writing with a global hotkey — in any app.\n\nOne quick permission and you're done.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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
                Text("Accessibility access granted. LingoPulse can now read and refine text in any app.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 40)
            } else {
                Text("LingoPulse needs Accessibility access to read and refine selected text.\n\nStep 1: Open System Settings → Privacy & Security → Accessibility. Toggle LingoPulse ON.\nStep 2: Restart LingoPulse so the new permission takes effect (macOS caches this per-process).")
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

    private var navigationBar: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { i in
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

            if step < 1 {
                Button("Next") { step += 1 }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Finish") { onComplete() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!axGranted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func requestAXAccess() {
        let opts: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private func startAXPolling() {
        guard axPollTask == nil else { return }
        axGranted = AXIsProcessTrusted()
        if axGranted { return }
        axPollTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                if Task.isCancelled { return }
                let trusted = AXIsProcessTrusted()
                if trusted && !axGranted {
                    axGranted = true
                    stopAXPolling()
                    return
                }
            }
        }
    }

    private func stopAXPolling() {
        axPollTask?.cancel()
        axPollTask = nil
    }

    private func relaunchApp() {
        stopAXPolling()
        guard let bundlePath = Bundle.main.bundlePath as String? else {
            NSApp.terminate(nil)
            return
        }
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundlePath]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.terminate(nil)
        }
    }
}
