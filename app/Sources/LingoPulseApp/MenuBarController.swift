import AppKit

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let coordinator: AppCoordinator
    private var personalDictWindow: PersonalDictWindowController?
    private var settingsWindow: SettingsWindowController?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            button.title = "✏️"
            button.toolTip = "LingoPulse"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Refine Selection (⌘⌥G)", action: #selector(refineNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Daemon Status…", action: #selector(checkStatus), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Personal Dictionary…", action: #selector(openPersonalDict), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit LingoPulse", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    @MainActor @objc private func refineNow() {
        coordinator.refineFocusedSelection()
    }

    @MainActor @objc private func checkStatus() {
        coordinator.fetchStatusAndShowAlert()
    }

    @MainActor @objc private func openPersonalDict() {
        if personalDictWindow == nil {
            personalDictWindow = PersonalDictWindowController(daemon: coordinator.daemonClient)
        }
        personalDictWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(daemon: coordinator.daemonClient)
        }
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
