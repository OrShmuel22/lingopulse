import AppKit
import ApplicationServices

private let terminalApps: Set<String> = ["iTerm2", "Terminal", "Alacritty", "WezTerm", "Hyper", "Warp"]

final class AXLiveObserver {
    var onTextChange: ((String, String, AXUIElement) -> Void)?

    private var axObserver: ApplicationServices.AXObserver?
    private var observedPID: pid_t = 0
    private var focusedElement: AXUIElement?
    private var currentAppName: String = ""
    private var appActivationObserver: NSObjectProtocol?

    func start() {
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.attachToApp(app)
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication {
            attachToApp(frontmost)
        }
    }

    func stop() {
        detachCurrent()
        if let obs = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appActivationObserver = nil
        }
    }

    deinit {
        stop()
    }

    private func attachToApp(_ app: NSRunningApplication) {
        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        guard !terminalApps.contains(appName) else { return }
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
            NSLog("LingoPulse AX: failed to create observer for \(appName) (\(createResult.rawValue))")
            return
        }

        axObserver = observer
        observedPID = pid

        let appElement = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString, selfPtr)

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        NSLog("LingoPulse AX: attached to \(appName)")
    }

    private func detachCurrent() {
        guard let observer = axObserver else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        if observedPID != 0 {
            let appElement = AXUIElementCreateApplication(observedPID)
            AXObserverRemoveNotification(observer, appElement, kAXFocusedUIElementChangedNotification as CFString)
            if let element = focusedElement {
                AXObserverRemoveNotification(observer, element, kAXValueChangedNotification as CFString)
            }
        }
        axObserver = nil
        focusedElement = nil
        observedPID = 0
    }

    // Called from axCallback which fires on CFRunLoopGetMain — safe to use MainActor.assumeIsolated.
    fileprivate func handleAXEvent(notification: String, element: AXUIElement) {
        guard AXIsProcessTrusted() else { return }
        guard let observer = axObserver else { return }

        if notification == kAXFocusedUIElementChangedNotification {
            if let oldElement = focusedElement {
                AXObserverRemoveNotification(observer, oldElement, kAXValueChangedNotification as CFString)
            }
            focusedElement = element
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
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
            onTextChange?(text, currentAppName, element)
        }
    }
}

private let axCallback: AXObserverCallback = { observer, element, notification, refcon in
    guard let refcon = refcon else { return }
    let me = Unmanaged<AXLiveObserver>.fromOpaque(refcon).takeUnretainedValue()
    me.handleAXEvent(notification: notification as String, element: element)
}
