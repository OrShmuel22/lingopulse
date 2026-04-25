import AppKit
import ApplicationServices

final class AXLiveObserver {
    var onTextChange: ((String, String, AXUIElement) -> Void)?

    private var axObserver: ApplicationServices.AXObserver?
    private var observedPID: pid_t = 0
    private var observedAppElement: AXUIElement?
    private var focusedElement: AXUIElement?
    private var currentAppName: String = ""
    private var appActivationObserver: NSObjectProtocol?
    private var trustPollTimer: Timer?

    func start() {
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.attachToApp(app)
        }

        if AXIsProcessTrusted() {
            if let frontmost = NSWorkspace.shared.frontmostApplication {
                attachToApp(frontmost)
            }
        } else {
            startTrustPolling()
        }
    }

    func stop() {
        trustPollTimer?.invalidate()
        trustPollTimer = nil
        detachCurrent()
        if let obs = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appActivationObserver = nil
        }
    }

    deinit {
        stop()
    }

    private func startTrustPolling() {
        guard trustPollTimer == nil else { return }
        trustPollTimer = Timer.scheduledTimer(withTimeInterval: Constants.Timing.axTrustPollSeconds, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.trustPollTimer = nil
                if let frontmost = NSWorkspace.shared.frontmostApplication {
                    self.attachToApp(frontmost)
                }
            }
        }
    }

    private func attachToApp(_ app: NSRunningApplication) {
        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        guard AXIsProcessTrusted() else { return }
        // Called on main queue (notification observer uses queue: .main)
        let isEnabled = MainActor.assumeIsolated { Preferences.shared.enabled }
        guard isEnabled else { return }

        detachCurrent()

        let pid = app.processIdentifier
        currentAppName = appName

        var observer: ApplicationServices.AXObserver?
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let createResult = AXObserverCreate(pid, axCallback, &observer)
        guard createResult == .success, let observer = observer else {
            Log.error("AX: failed to create observer for \(appName) (\(createResult.rawValue))")
            return
        }

        axObserver = observer
        observedPID = pid

        let appElement = AXUIElementCreateApplication(pid)
        observedAppElement = appElement
        AXObserverAddNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString, selfPtr)

        // Subscribe to value changes on the currently focused element. Without this,
        // typing in an already-focused field (the common case) never fires our callback
        // because kAXFocusedUIElementChangedNotification only fires on focus *changes*.
        var currentFocused: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &currentFocused)
        if focusErr == .success, let focusedAny = currentFocused,
           let element = AXClient.asAXUIElement(focusedAny) {
            focusedElement = element
            AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, selfPtr)
            Log.debug("AX: subscribed to value changes on initial focused element of \(appName)")
        } else {
            Log.debug("AX: no focused element on attach to \(appName) (err=\(focusErr.rawValue))")
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        Log.debug("AX: attached to \(appName)")
    }

    private func detachCurrent() {
        guard let observer = axObserver else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        if let appElement = observedAppElement {
            AXObserverRemoveNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString)
            if let element = focusedElement {
                AXObserverRemoveNotification(observer, element, kAXValueChangedNotification as CFString)
            }
        }
        axObserver = nil
        observedAppElement = nil
        focusedElement = nil
        observedPID = 0
    }

    // Called from axCallback which fires on CFRunLoopGetMain — safe to use MainActor.assumeIsolated.
    fileprivate func handleAXEvent(notification: String, element: AXUIElement) {
        guard AXIsProcessTrusted() else { return }
        guard let observer = axObserver else { return }

        if notification == kAXFocusedUIElementChangedNotification {
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            if let oldElement = focusedElement {
                AXObserverRemoveNotification(observer, oldElement, kAXValueChangedNotification as CFString)
            }
            focusedElement = element
            AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, selfPtr)
        } else if notification == kAXValueChangedNotification {
            let (enabled, excluded) = MainActor.assumeIsolated {
                (Preferences.shared.enabled, Preferences.shared.excludedApps)
            }
            guard enabled else { return }
            guard !excluded.contains(currentAppName) else { return }
            var valueRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
            guard err == .success, let text = valueRef as? String, !text.isEmpty else { return }
            Log.debug("AX: value changed in \(currentAppName) (\(text.count) chars)")
            onTextChange?(text, currentAppName, element)
        }
    }
}

private let axCallback: AXObserverCallback = { observer, element, notification, refcon in
    guard let refcon = refcon else { return }
    let me = Unmanaged<AXLiveObserver>.fromOpaque(refcon).takeUnretainedValue()
    me.handleAXEvent(notification: notification as String, element: element)
}
