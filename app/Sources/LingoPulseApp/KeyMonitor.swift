import AppKit

final class KeyMonitor {
    var onTab: (() -> Void)?
    var onEsc: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onArrowUp: (() -> Void)?
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
        let downKey: UInt16 = 125
        let upKey: UInt16 = 126
        switch event.keyCode {
        case tabKey:
            onTab?()
            return nil
        case escKey:
            onEsc?()
            return nil
        case downKey:
            onArrowDown?()
            return nil
        case upKey:
            onArrowUp?()
            return nil
        default:
            onOtherKey?()
            return event
        }
    }
}
