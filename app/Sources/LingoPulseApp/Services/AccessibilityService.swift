import AppKit
import ApplicationServices

protocol AccessibilityServicing {
    var isTrusted: Bool { get }
    func readSelection() -> Selection?
    @discardableResult func writeFocusedValue(_ text: String) -> Bool
}

final class AccessibilityService: AccessibilityServicing {
    var isTrusted: Bool { AXIsProcessTrusted() }

    func readSelection() -> Selection? {
        guard let (text, app, element) = AXClient.readSelection() else { return nil }
        return Selection(text: text, appName: app, element: element)
    }

    @discardableResult func writeFocusedValue(_ text: String) -> Bool {
        AXClient.writeFocusedValue(text)
    }
}
