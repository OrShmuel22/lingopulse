import AppKit
import ApplicationServices
import Combine
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var triggerMonitor: TriggerMonitor?
    private var quickActionPanel: QuickActionPanel?
    private var shellBridge: ShellBridgeServer?
    private var coordinator: AppCoordinator?
    private var prefsObservers: Set<AnyCancellable> = []
    private var onboardingWindow: OnboardingWindow?
    private var fixer: Fixer?
    private var accessibility: AccessibilityServicing?
    private var liveMonitor: LiveTextMonitor?
    private var ghostOverlay: GhostOverlayWindow?
    private var keepaliveOrchestrator: KeepaliveOrchestrator?
    private var healthMonitor: HealthMonitor?

    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        Notifications.requestAuthorizationIfNeeded()

        if !AXClient.ensureTrusted() {
            Log.error("Accessibility not granted yet — grant in System Settings → Privacy → Accessibility, then restart.")
        }

        // One-shot migration: clear stale KeyboardShortcuts_ UserDefaults entries written by v1.
        if !UserDefaults.standard.bool(forKey: "lp.hotkeyMigration_v2") {
            UserDefaults.standard.dictionaryRepresentation().keys
                .filter { $0.hasPrefix("KeyboardShortcuts_") }
                .forEach { UserDefaults.standard.removeObject(forKey: $0) }
            UserDefaults.standard.set(true, forKey: "lp.hotkeyMigration_v2")
        }

        let prefs = Preferences.shared

        Log.setLevel(prefs.logLevel)
        observePref(prefs.$logLevel) { Log.setLevel($0) }

        let accessibility = AccessibilityService()
        self.accessibility = accessibility

        let config = AppConfig.shared
        let ollama = OllamaService()
        let history = HistoryStore()
        let ringPath = config.path(at: "ring_buffer.path")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/lingopulse/ring.json")
        let ringSize: Int = config.value(at: "ring_buffer.size") ?? 5
        let ring = RingBuffer(fileURL: ringPath, size: ringSize)
        let spell: SpellChecking = SpellCheck()
        let fixer = Fixer(ollama: ollama, config: config, history: history, ring: ring, spellCheck: spell)
        self.fixer = fixer

        let keepalive = KeepaliveOrchestrator(ollama: ollama, config: config)
        keepalive.start()
        self.keepaliveOrchestrator = keepalive

        let coordinator = AppCoordinator(fixer: fixer, accessibility: accessibility)
        self.coordinator = coordinator

        let menuBar = MenuBarController(coordinator: coordinator)
        self.menuBar = menuBar
        coordinator.onRefiningChanged = { [weak menuBar] on in
            menuBar?.setRefining(on)
        }

        let health = HealthMonitor(ollama: ollama)
        health.onChange = { [weak menuBar] h in
            menuBar?.setHealth(h)
        }
        health.start()
        self.healthMonitor = health

        let panel = QuickActionPanel()
        self.quickActionPanel = panel

        let monitor = TriggerMonitor(
            onSingleKey: { [weak coordinator] in coordinator?.refineFocusedSelection() },
            onDoubleTap: { [weak self] in self?.showQuickActionPanel() },
            singleKey: TriggerMonitor.SingleKey(prefValue: prefs.triggerSingleKey),
            doubleTapModifier: TriggerMonitor.DoubleTapMod(prefValue: prefs.triggerDoubleTapMod)
        )
        monitor.start()
        self.triggerMonitor = monitor

        observePref(prefs.$triggerSingleKey) { [weak self] _ in
            self?.rebuildTriggerMonitor(prefs: prefs, coordinator: coordinator)
        }
        observePref(prefs.$triggerDoubleTapMod) { [weak self] _ in
            self?.rebuildTriggerMonitor(prefs: prefs, coordinator: coordinator)
        }

        if !prefs.onboardingCompleted {
            let onboarding = OnboardingWindow()
            self.onboardingWindow = onboarding
            onboarding.show {
                prefs.onboardingCompleted = true
                self.onboardingWindow = nil
            }
        }

        applyLiveMode(prefs.liveModeEnabled, prefs: prefs)
        observePref(prefs.$liveModeEnabled) { [weak self] enabled in
            self?.applyLiveMode(enabled, prefs: prefs)
        }

        applyShellBridge(prefs.shellBridgeEnabled, fixer: fixer)
        observePref(prefs.$shellBridgeEnabled) { [weak self] enabled in
            self?.applyShellBridge(enabled, fixer: fixer)
        }

        applyLaunchAtLogin(prefs.launchAtLogin)
        observePref(prefs.$launchAtLogin) { [weak self] enabled in
            self?.applyLaunchAtLogin(enabled)
        }

        Log.info("app launched, menu bar ready, trigger monitor started.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        keepaliveOrchestrator?.stop()
        healthMonitor?.stop()
        Log.info("shutting down.")
    }

    private func observePref<P: Publisher>(_ publisher: P, action: @escaping (P.Output) -> Void)
    where P.Failure == Never {
        publisher.dropFirst().sink(receiveValue: action).store(in: &prefsObservers)
    }

    @MainActor private func showQuickActionPanel() {
        guard let coordinator = coordinator, let panel = quickActionPanel else { return }
        let anchor: AXUIElement? = {
            guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            var f: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &f) == .success else { return nil }
            return AXClient.asAXUIElement(f)
        }()
        panel.show(anchor: anchor) { action in
            guard let action = action else { return }
            switch action {
            case .refine:       coordinator.refineFocusedSelection()
            case .preview:      coordinator.previewSelection()
            case .tone:         coordinator.refineWithTone()
            case .undo:         coordinator.undoLast()
            case .dictionary:   coordinator.lookupWord()
            case .captureStyle: coordinator.captureStyleExample()
            }
        }
    }

    @MainActor private func rebuildTriggerMonitor(prefs: Preferences, coordinator: AppCoordinator) {
        triggerMonitor?.stop()
        let monitor = TriggerMonitor(
            onSingleKey: { [weak coordinator] in coordinator?.refineFocusedSelection() },
            onDoubleTap: { [weak self] in self?.showQuickActionPanel() },
            singleKey: TriggerMonitor.SingleKey(prefValue: prefs.triggerSingleKey),
            doubleTapModifier: TriggerMonitor.DoubleTapMod(prefValue: prefs.triggerDoubleTapMod)
        )
        monitor.start()
        triggerMonitor = monitor
    }

    @MainActor private func applyShellBridge(_ enabled: Bool, fixer: Fixer) {
        if enabled {
            guard shellBridge == nil else { return }
            let server = ShellBridgeServer(refine: { [weak fixer] text in
                guard let fixer = fixer else { throw ShellBridgeError.tokenGeneration }
                // Capture frontmost app name dynamically at each refine call.
                let app = await MainActor.run {
                    NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
                }
                let result = try await fixer.refine(selection: text, app: app)
                return result.refined
            })
            do {
                try server.start()
                shellBridge = server
                Log.info("ShellBridge started on port \(server.port ?? 0)")
            } catch {
                Log.error("ShellBridge start failed: \(error)")
                Notifications.show(title: "LingoPulse", body: "Shell bridge failed to start: \(error)")
            }
        } else {
            shellBridge?.stop()
            shellBridge = nil
        }
    }

    @MainActor private func applyLiveMode(_ enabled: Bool, prefs: Preferences) {
        if enabled {
            guard liveMonitor == nil, let fixer = fixer else { return }
            if ghostOverlay == nil { ghostOverlay = GhostOverlayWindow() }
            let monitor = LiveTextMonitor(
                fixer: fixer,
                excludedApps: { [weak prefs] in prefs?.liveModeExcludedApps ?? [] },
                debounceSeconds: { [weak prefs] in prefs?.debounceSeconds ?? 1.5 },
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
        // Targeted-element write failed — fall back to focused-field clipboard paste.
        accessibility?.applyTextWithFallback(s.refined, restoreDelayMs: 150)
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
