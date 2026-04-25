import AppKit
import ApplicationServices

protocol AccessibilityServicing {
    var isTrusted: Bool { get }
    func readSelection() -> Selection?
    @discardableResult func writeFocusedValue(_ text: String) -> Bool
    func startListening(onChange: @escaping (Selection) -> Void)
    func stopListening()
}

final class AccessibilityService: AccessibilityServicing {
    private let observer = AXLiveObserver()

    var isTrusted: Bool { AXIsProcessTrusted() }

    func readSelection() -> Selection? {
        guard let (text, app, element) = AXClient.readSelection() else { return nil }
        return Selection(text: text, appName: app, element: element)
    }

    @discardableResult func writeFocusedValue(_ text: String) -> Bool {
        AXClient.writeFocusedValue(text)
    }

    func startListening(onChange: @escaping (Selection) -> Void) {
        observer.onTextChange = { text, app, element in
            onChange(Selection(text: text, appName: app, element: element))
        }
        observer.start()
    }

    func stopListening() {
        observer.stop()
    }
}
