import AppKit
import ApplicationServices
import Combine

struct LiveSuggestion {
    let element: AXUIElement
    let original: String
    let refined: String
    let anchorRect: CGRect?
}

@MainActor
final class LiveTextMonitor {
    private let fixer: Fixer
    private let onSuggestion: (LiveSuggestion) -> Void

    private var workspaceObservers: Set<AnyCancellable> = []
    private var currentAppPID: pid_t?
    private(set) var axObserver: AXObserver?
    private var focusedElement: AXUIElement?
    private(set) var debounceTask: Task<Void, Never>?

    private let debounceSeconds: () -> Double
    private let excludedApps: () -> Set<String>

    init(fixer: Fixer,
         excludedApps: @escaping () -> Set<String>,
         debounceSeconds: @escaping () -> Double,
         onSuggestion: @escaping (LiveSuggestion) -> Void) {
        self.fixer = fixer
        self.excludedApps = excludedApps
        self.debounceSeconds = debounceSeconds
        self.onSuggestion = onSuggestion
    }

    func start() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .sink { [weak self] app in self?.attach(to: app) }
            .store(in: &workspaceObservers)

        if let cur = NSWorkspace.shared.frontmostApplication { attach(to: cur) }
    }

    func stop() {
        workspaceObservers.removeAll()
        detach()
    }

    func attach(to app: NSRunningApplication) {
        detach()
        guard let name = app.localizedName, !excludedApps().contains(name) else {
            Log.info("LiveMonitor: skipping excluded app \(app.localizedName ?? "?")")
            return
        }
        let pid = app.processIdentifier
        currentAppPID = pid

        let appElement = AXUIElementCreateApplication(pid)

        var observer: AXObserver?
        let cb: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon = refcon else { return }
            let monitor = Unmanaged<LiveTextMonitor>.fromOpaque(refcon).takeUnretainedValue()
            let notifStr = notification as String
            Task { @MainActor in monitor.handleNotification(notifStr, element: element) }
        }
        let createStatus = AXObserverCreate(pid, cb, &observer)
        guard createStatus == .success, let obs = observer else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(obs, appElement, kAXFocusedUIElementChangedNotification as CFString, refcon)

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        self.axObserver = obs

        var focused: AnyObject?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let elem = AXClient.asAXUIElement(focused as CFTypeRef?) {
            updateFocusedElement(elem)
        }
    }

    private func updateFocusedElement(_ element: AXUIElement) {
        if let old = focusedElement, let obs = axObserver {
            AXObserverRemoveNotification(obs, old, kAXValueChangedNotification as CFString)
            AXObserverRemoveNotification(obs, old, kAXSelectedTextChangedNotification as CFString)
        }
        focusedElement = element
        guard let obs = axObserver else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(obs, element, kAXValueChangedNotification as CFString, refcon)
        AXObserverAddNotification(obs, element, kAXSelectedTextChangedNotification as CFString, refcon)
    }

    private func handleNotification(_ name: String, element: AXUIElement) {
        switch name {
        case kAXFocusedUIElementChangedNotification:
            updateFocusedElement(element)
        case kAXValueChangedNotification, kAXSelectedTextChangedNotification:
            scheduleDebouncedRefine()
        default:
            break
        }
    }

    func scheduleDebouncedRefine() {
        debounceTask?.cancel()
        let ms = max(100, Int(debounceSeconds() * 1000))
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled else { return }
            await runRefine()
        }
    }

    private func runRefine() async {
        guard let element = focusedElement else { return }
        guard let value = readValue(of: element),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if value.count < 12 { return }

        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        do {
            let result = try await fixer.refine(selection: value, app: app)
            if result.refined == result.original { return }
            let bounds = CaretLocator.locate(in: element)
            onSuggestion(LiveSuggestion(
                element: element,
                original: result.original,
                refined: result.refined,
                anchorRect: bounds
            ))
        } catch FixerError.ollama(.busy) {
            // Another refine in flight — skip silently
        } catch {
            Log.error("LiveMonitor refine error: \(error)")
        }
    }

    private func readValue(of element: AXUIElement) -> String? {
        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &raw) == .success,
              let s = raw as? String else { return nil }
        return s
    }

    private func detach() {
        if let obs = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        axObserver = nil
        focusedElement = nil
        currentAppPID = nil
        debounceTask?.cancel()
        debounceTask = nil
    }
}
