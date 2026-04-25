import AppKit
import CoreGraphics

final class KeyMonitor {
    var onTab: (() -> Void)?
    var onEsc: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onArrowUp: (() -> Void)?
    var onOtherKey: (() -> Void)?

    fileprivate var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var startedAt: Date?

    /// Grace period after start during which non-Tab/Esc/arrow keystrokes don't dismiss.
    /// User typically pauses, chip appears, types one more char before deciding — that
    /// shouldn't kill the suggestion.
    private let graceSeconds: TimeInterval = 0.6

    func start() {
        startedAt = Date()
        guard tap == nil else { return }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyTapCallback,
            userInfo: selfPtr
        ) else {
            Log.error("KeyMonitor: failed to create CGEventTap (Accessibility may be denied)")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.tap = eventTap
        self.runLoopSource = source
        Log.debug("KeyMonitor: tap installed")
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            self.runLoopSource = nil
        }
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            self.tap = nil
        }
        startedAt = nil
        Log.debug("KeyMonitor: tap removed")
    }

    /// Called from the CGEventTap callback. Returns true if event should be consumed.
    fileprivate func handle(keyCode: Int64) -> Bool {
        let tabKey: Int64 = 48
        let escKey: Int64 = 53
        let returnKey: Int64 = 36
        let downKey: Int64 = 125
        let upKey: Int64 = 126

        switch keyCode {
        case tabKey:
            DispatchQueue.main.async { [weak self] in self?.onTab?() }
            return true
        case escKey:
            DispatchQueue.main.async { [weak self] in self?.onEsc?() }
            return true
        case downKey:
            DispatchQueue.main.async { [weak self] in self?.onArrowDown?() }
            return true
        case upKey:
            DispatchQueue.main.async { [weak self] in self?.onArrowUp?() }
            return true
        case returnKey:
            DispatchQueue.main.async { [weak self] in self?.onOtherKey?() }
            return false
        default:
            if let started = startedAt, Date().timeIntervalSince(started) < graceSeconds {
                return false
            }
            DispatchQueue.main.async { [weak self] in self?.onOtherKey?() }
            return false
        }
    }
}

private let keyTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let info = userInfo {
            let monitor = Unmanaged<KeyMonitor>.fromOpaque(info).takeUnretainedValue()
            if let tap = monitor.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown, let info = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let monitor = Unmanaged<KeyMonitor>.fromOpaque(info).takeUnretainedValue()
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let consume = monitor.handle(keyCode: keyCode)
    return consume ? nil : Unmanaged.passUnretained(event)
}
