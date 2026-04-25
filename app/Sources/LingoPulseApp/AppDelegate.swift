import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotkeys: HotkeyManager?
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AXClient.ensureTrusted() {
            NSLog("LingoPulse: Accessibility not granted yet — grant in System Settings → Privacy → Accessibility, then restart.")
        }

        let coordinator = AppCoordinator(daemon: DaemonClient(baseURL: URL(string: "http://127.0.0.1:17823")!))
        self.coordinator = coordinator

        self.menuBar = MenuBarController(coordinator: coordinator)
        self.hotkeys = HotkeyManager(coordinator: coordinator)

        NSLog("LingoPulse: app launched, menu bar ready, hotkeys registered.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("LingoPulse: shutting down.")
    }
}
