import AppKit
import ApplicationServices
import Combine
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotkeys: HotkeyManager?
    private var coordinator: AppCoordinator?
    private var prefsObservers: Set<AnyCancellable> = []
    private var onboardingWindow: OnboardingWindow?
    private var fixer: Fixer?
    private var liveMonitor: LiveTextMonitor?
    private var ghostOverlay: GhostOverlayWindow?

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        Notifications.requestAuthorizationIfNeeded()

        if !AXClient.ensureTrusted() {
            Log.error("Accessibility not granted yet — grant in System Settings → Privacy → Accessibility, then restart.")
        }

        let prefs = Preferences.shared

        Log.setLevel(prefs.logLevel)
        prefs.$logLevel
            .dropFirst()
            .sink { Log.setLevel($0) }
            .store(in: &prefsObservers)

        let accessibility = AccessibilityService()

        let config = AppConfig.shared
        let ollama = OllamaService()
        let history = HistoryStore()
        let ringPath = config.path(at: "ring_buffer.path")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/lingopulse/ring.json")
        let ringSize: Int = config.value(at: "ring_buffer.size") ?? 5
        let ring = RingBuffer(fileURL: ringPath, size: ringSize)
        let fixer = Fixer(ollama: ollama, config: config, history: history, ring: ring)
        self.fixer = fixer

        let coordinator = AppCoordinator(fixer: fixer, accessibility: accessibility)
        self.coordinator = coordinator

        self.menuBar = MenuBarController(coordinator: coordinator)
        self.hotkeys = HotkeyManager(coordinator: coordinator)

        if !prefs.onboardingCompleted {
            let onboarding = OnboardingWindow()
            self.onboardingWindow = onboarding
            onboarding.show {
                prefs.onboardingCompleted = true
                self.onboardingWindow = nil
            }
        }

        applyLiveMode(prefs.liveModeEnabled, prefs: prefs)
        prefs.$liveModeEnabled
            .dropFirst()
            .sink { [weak self] enabled in self?.applyLiveMode(enabled, prefs: prefs) }
            .store(in: &prefsObservers)

        applyLaunchAtLogin(prefs.launchAtLogin)
        prefs.$launchAtLogin
            .dropFirst()
            .sink { [weak self] enabled in self?.applyLaunchAtLogin(enabled) }
            .store(in: &prefsObservers)

        Log.info("app launched, menu bar ready, hotkeys registered.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.info("shutting down.")
    }

    @MainActor private func applyLiveMode(_ enabled: Bool, prefs: Preferences) {
        if enabled {
            guard liveMonitor == nil, let fixer = fixer else { return }
            if ghostOverlay == nil { ghostOverlay = GhostOverlayWindow() }
            let monitor = LiveTextMonitor(
                fixer: fixer,
                excludedApps: { [weak prefs] in prefs?.liveModeExcludedApps ?? [] },
                onSuggestion: { [weak self] suggestion in
                    self?.ghostOverlay?.show(suggestion: suggestion, onApply: {
                        self?.applyLiveSuggestion(suggestion)
                    })
                }
            )
            monitor.start()
            liveMonitor = monitor
        } else {
            liveMonitor?.stop()
            liveMonitor = nil
            ghostOverlay?.close()
        }
    }

    @MainActor private func applyLiveSuggestion(_ s: LiveSuggestion) {
        let result = AXUIElementSetAttributeValue(s.element, kAXValueAttribute as CFString, s.refined as CFString)
        if result == .success { return }

        let snap = ClipboardSnapshot()
        ClipboardService.copy(s.refined)
        Task { @MainActor in
            await SelectionService.pasteTextViaShortcut(s.refined)
            try? await Task.sleep(for: .milliseconds(150))
            snap.restore()
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.error("SMAppService \(enabled ? "register" : "unregister") failed: \(error)")
        }
    }

}
