import AppKit
import ApplicationServices

enum AXClient {
    static func ensureTrusted() -> Bool {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Returns selection text + frontmost app bundle name.
    static func readSelection() -> (text: String, app: String)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let pid = app.processIdentifier

        let appElement = AXUIElementCreateApplication(pid)
        guard let focused = copyAttribute(appElement, kAXFocusedUIElementAttribute) else { return nil }
        let element = focused as! AXUIElement

        if let selected = copyAttribute(element, kAXSelectedTextAttribute) as? String, !selected.isEmpty {
            return (selected, appName)
        }
        if let value = copyAttribute(element, kAXValueAttribute) as? String, !value.isEmpty {
            return (value, appName)
        }
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
