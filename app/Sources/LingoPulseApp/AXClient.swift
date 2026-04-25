import AppKit
import ApplicationServices

enum AXClient {
    static func ensureTrusted() -> Bool {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Returns selection text + frontmost app bundle name.
    static func readSelection() -> (text: String, app: String)? {
        let trustedNow = AXIsProcessTrusted()
        guard let app = NSWorkspace.shared.frontmostApplication else {
            NSLog("LingoPulse AX: no frontmost app (trusted=\(trustedNow))")
            return nil
        }
        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let pid = app.processIdentifier
        NSLog("LingoPulse AX: frontmost=\(appName) pid=\(pid) trusted=\(trustedNow)")

        let appElement = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        let focusedErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusedErr == .success, let focusedAny = focusedRef else {
            NSLog("LingoPulse AX: focus read failed (err=\(focusedErr.rawValue)) — likely AX permission denied for this app or app blocks AX")
            return nil
        }
        let element = focusedAny as! AXUIElement

        var selectedRef: CFTypeRef?
        let selErr = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef)
        if selErr == .success, let selected = selectedRef as? String, !selected.isEmpty {
            NSLog("LingoPulse AX: got kAXSelectedText (\(selected.count) chars)")
            return (selected, appName)
        }

        var valueRef: CFTypeRef?
        let valErr = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        if valErr == .success, let value = valueRef as? String, !value.isEmpty {
            NSLog("LingoPulse AX: got kAXValue (\(value.count) chars)")
            return (value, appName)
        }

        NSLog("LingoPulse AX: focus reachable but no text — selErr=\(selErr.rawValue) valErr=\(valErr.rawValue). Try selecting text first.")
        return nil
    }

    /// Replace the value of the focused element. Returns true if write succeeded.
    static func writeFocusedValue(_ text: String) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = copyAttribute(appElement, kAXFocusedUIElementAttribute) else { return false }
        let element = focused as! AXUIElement

        let cfText = text as CFString
        let setResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, cfText)
        return setResult == .success
    }

    private static func copyAttribute(_ element: AXUIElement, _ attr: String) -> AnyObject? {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attr as CFString, &ref)
        guard err == .success else { return nil }
        return ref as AnyObject?
    }
}
