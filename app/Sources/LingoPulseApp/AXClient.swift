import AppKit
import ApplicationServices

enum AXClient {
    static func ensureTrusted() -> Bool {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Returns selection text, frontmost app bundle name, and the focused AXUIElement.
    static func readSelection() -> (text: String, app: String, element: AXUIElement?)? {
        let trustedNow = AXIsProcessTrusted()
        guard let app = NSWorkspace.shared.frontmostApplication else {
            Log.debug("AX: no frontmost app (trusted=\(trustedNow))")
            return nil
        }
        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let pid = app.processIdentifier
        Log.debug("AX: frontmost=\(appName) pid=\(pid) trusted=\(trustedNow)")

        let appElement = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?
        let focusedErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusedErr == .success, let focusedAny = focusedRef else {
            Log.error("AX: focus read failed (err=\(focusedErr.rawValue)) — likely AX permission denied for this app or app blocks AX")
            return nil
        }
        guard let element = asAXUIElement(focusedAny) else {
            Log.error("AX: focused element is not AXUIElement")
            return nil
        }

        var selectedRef: CFTypeRef?
        let selErr = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef)
        if selErr == .success, let selected = selectedRef as? String, !selected.isEmpty {
            Log.debug("AX: got kAXSelectedText (\(selected.count) chars)")
            return (selected, appName, element)
        }

        var valueRef: CFTypeRef?
        let valErr = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        if valErr == .success, let value = valueRef as? String, !value.isEmpty {
            Log.debug("AX: got kAXValue (\(value.count) chars)")
            return (value, appName, element)
        }

        Log.debug("AX: focus reachable but no text — selErr=\(selErr.rawValue) valErr=\(valErr.rawValue). Try selecting text first.")
        return nil
    }

    /// Replace the value of the focused element. Returns true if write succeeded.
    static func writeFocusedValue(_ text: String) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = copyAttribute(appElement, kAXFocusedUIElementAttribute) else { return false }
        guard let element = asAXUIElement(focused) else { return false }
        return writeValue(to: element, text: text)
    }

    /// Replace the value of a specific captured AX element. Use this when the
    /// element handle was captured at selection-read time, so the write can
    /// target it directly even if focus has since moved (e.g. while a preview
    /// panel was on screen). Returns true on success.
    static func writeValue(to element: AXUIElement, text: String) -> Bool {
        let cfText = text as CFString
        let setResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, cfText)
        return setResult == .success
    }

    /// Make `element` the system-wide focused UI element. Used before
    /// synthesizing keyboard shortcuts (⌘A / ⌘V) to ensure they hit the right
    /// field — important for URL bars which lose focus when a panel takes key
    /// status.
    @discardableResult
    static func setSystemwideFocus(_ element: AXUIElement) -> Bool {
        let systemwide = AXUIElementCreateSystemWide()
        let result = AXUIElementSetAttributeValue(systemwide, kAXFocusedUIElementAttribute as CFString, element)
        return result == .success
    }

    static func axPoint(from ref: CFTypeRef?) -> CGPoint? {
        guard let ref = ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        let value = ref as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    static func axSize(from ref: CFTypeRef?) -> CGSize? {
        guard let ref = ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        let value = ref as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    static func asAXUIElement(_ ref: CFTypeRef?) -> AXUIElement? {
        guard let ref = ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private static func copyAttribute(_ element: AXUIElement, _ attr: String) -> CFTypeRef? {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attr as CFString, &ref)
        guard err == .success else { return nil }
        return ref
    }
}
