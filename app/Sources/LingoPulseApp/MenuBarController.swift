import AppKit

final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let coordinator: AppCoordinator

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
        menu.addItem(NSMenuItem(title: "Quit LingoPulse", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    @objc private func refineNow() {
        coordinator.refineFocusedSelection()
    }

    @objc private func checkStatus() {
        coordinator.fetchStatusAndShowAlert()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
