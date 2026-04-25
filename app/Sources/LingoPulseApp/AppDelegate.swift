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
        let url = URL(string: prefs.daemonURL) ?? URL(string: "http://127.0.0.1:17823")!
        let coordinator = AppCoordinator(daemon: DaemonClient(baseURL: url))
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
