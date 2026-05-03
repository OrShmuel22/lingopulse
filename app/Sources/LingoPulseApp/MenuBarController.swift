import AppKit
import Combine

enum AppHealth: Equatable {
    case ok
    case axRevoked
    case daemonDown
}

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let coordinator: AppCoordinator
    private var settingsWindow: SettingsWindowController?
    private var onboardingWindow: OnboardingWindow?
    private var refineMenuItem: NSMenuItem?
    private var statusMenuItem: NSMenuItem?
    private var refiningSpinTask: Task<Void, Never>?
    private var prefsCancellables: Set<AnyCancellable> = []

    private var isRefining: Bool = false
    private var health: AppHealth = .ok

    private static let refiningFrames = ["⏳", "⌛️"]
    private static let idleTitle = "✏️"
    private static let axRevokedTitle = "⚠️"
    private static let daemonDownTitle = "🚫"

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configure()
        observePrefs()
    }

    private func observePrefs() {
        let prefs = Preferences.shared
        prefs.$fixerModel.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }.store(in: &prefsCancellables)
    }

    func setRefining(_ on: Bool) {
        isRefining = on
        refresh()
    }

    func setHealth(_ h: AppHealth) {
        guard h != health else { return }
        health = h
        refresh()
    }

    private func activeModelTooltip() -> String {
        let prefs = Preferences.shared
        let fixer = prefs.fixerModel ?? "config default"
        return "LingoPulse\nRefine: \(fixer)"
    }

    private func refresh() {
        guard let button = statusItem.button else { return }
        refiningSpinTask?.cancel()
        refiningSpinTask = nil

        if isRefining {
            button.title = Self.refiningFrames[0]
            button.toolTip = "LingoPulse — refining…"
            refineMenuItem?.title = "Refining… (in flight)"
            refineMenuItem?.isEnabled = false
            statusMenuItem?.title = "Status: refining…"
            refiningSpinTask = Task { @MainActor [weak self] in
                var index = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(600))
                    if Task.isCancelled { return }
                    guard let self = self, let btn = self.statusItem.button else { return }
                    index = (index + 1) % Self.refiningFrames.count
                    btn.title = Self.refiningFrames[index]
                }
            }
            return
        }

        switch health {
        case .ok:
            button.title = Self.idleTitle
            button.toolTip = activeModelTooltip()
            statusMenuItem?.title = "Status: ready"
        case .axRevoked:
            button.title = Self.axRevokedTitle
            button.toolTip = "LingoPulse — Accessibility permission missing"
            statusMenuItem?.title = "Status: Accessibility permission missing"
        case .daemonDown:
            button.title = Self.daemonDownTitle
            button.toolTip = "LingoPulse — Ollama daemon unreachable"
            statusMenuItem?.title = "Status: Ollama daemon unreachable"
        }
        refineMenuItem?.title = "Refine Selection (⌘⌥G)"
        refineMenuItem?.isEnabled = (health == .ok)
    }

    private func configure() {
        if let button = statusItem.button {
            button.title = Self.idleTitle
            button.toolTip = "LingoPulse"
        }

        let menu = NSMenu()
        let statusItem = NSMenuItem(title: "Status: ready", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        self.statusMenuItem = statusItem
        menu.addItem(NSMenuItem.separator())

        let refineItem = NSMenuItem(title: "Refine Selection (⌘⌥G)", action: #selector(refineNow), keyEquivalent: "")
        menu.addItem(refineItem)
        self.refineMenuItem = refineItem
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Setup / Onboarding…", action: #selector(openOnboarding), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit LingoPulse", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }
        self.statusItem.menu = menu
    }

    @objc private func refineNow() {
        coordinator.refineFocusedSelection()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
        }
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = OnboardingWindow()
        }
        onboardingWindow?.show(onComplete: { [weak self] in
            self?.onboardingWindow = nil
        })
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
