import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotkeys: HotkeyManager?
    private var coordinator: AppCoordinator?
    private var prefsObservers: Set<AnyCancellable> = []

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

        let url = URL(string: prefs.daemonURL) ?? Constants.Daemon.defaultURL
        let daemon = DaemonClient(baseURL: url)
        let accessibility = AccessibilityService()
        let pipeline = SuggestionPipeline(daemon: daemon)
        let presenter = ChipPresenter()
        let coordinator = AppCoordinator(
            daemon: daemon,
            accessibility: accessibility,
            pipeline: pipeline,
            presenter: presenter
        )
        self.coordinator = coordinator

        if prefs.enabled {
            coordinator.startLiveListener()
        }

        self.menuBar = MenuBarController(coordinator: coordinator)
        self.hotkeys = HotkeyManager(
            coordinator: coordinator,
            keyCode: UInt32(prefs.hotkeyKeyCode),
            modifiers: prefs.hotkeyModifiers
        )

        observeRebinds(coordinator: coordinator)
        Log.info("app launched, menu bar ready, hotkeys registered.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.info("shutting down.")
    }

    @MainActor private func observeRebinds(coordinator: AppCoordinator) {
        let prefs = Preferences.shared
        prefs.$hotkeyKeyCode.combineLatest(prefs.$hotkeyModifiers)
            .dropFirst()
            .sink { [weak self] kc, mods in
                self?.hotkeys?.rebind(keyCode: UInt32(kc), modifiers: mods)
            }
            .store(in: &prefsObservers)

        prefs.$daemonURL
            .dropFirst()
            .sink { newURL in
                if let u = URL(string: newURL) {
                    coordinator.updateDaemonURL(u)
                }
            }
            .store(in: &prefsObservers)

        prefs.$enabled
            .dropFirst()
            .sink { enabled in
                if enabled {
                    coordinator.startLiveListener()
                } else {
                    coordinator.stopLiveListener()
                }
            }
            .store(in: &prefsObservers)
    }
}
