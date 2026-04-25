import AppKit

final class KeyMonitor {
    var onTab: (() -> Void)?
    var onEsc: (() -> Void)?
    var onOtherKey: (() -> Void)?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func start() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            return self?.handle(event) ?? event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handle(event)
        }
    }

    func stop() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
    }

    @discardableResult
    private func handle(_ event: NSEvent) -> NSEvent? {
        let tabKey: UInt16 = 48
        let escKey: UInt16 = 53
        switch event.keyCode {
        case tabKey:
            onTab?()
            return nil
        case escKey:
            onEsc?()
            return nil
        default:
            onOtherKey?()
            return event
        }
    }
}
