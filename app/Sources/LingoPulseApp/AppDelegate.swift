import AppKit
import Combine
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotkeys: HotkeyManager?
    private var coordinator: AppCoordinator?
    private var prefsObservers: Set<AnyCancellable> = []
    private var onboardingWindow: OnboardingWindow?

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
