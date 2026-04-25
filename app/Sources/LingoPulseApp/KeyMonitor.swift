import AppKit
import CoreGraphics

final class KeyMonitor {
    var onTab: (() -> Void)?
    var onEsc: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onArrowUp: (() -> Void)?
    var onSpace: (() -> Void)?
    var onReturn: (() -> Void)?
    var onCommandReturn: (() -> Void)?
    var onOtherKey: (() -> Void)?

    fileprivate var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var startedAt: Date?
    private var retainedSelfPtr: UnsafeMutableRawPointer?

    /// Grace period after start during which non-Tab/Esc/arrow keystrokes don't dismiss.
    /// User typically pauses, chip appears, types one more char before deciding — that
    /// shouldn't kill the suggestion.
    private let graceSeconds: TimeInterval = Constants.Timing.keyGracePeriodSeconds

    func start() {
        startedAt = Date()
        guard tap == nil else { return }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        self.retainedSelfPtr = selfPtr

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyTapCallback,
            userInfo: selfPtr
        ) else {
            Log.error("KeyMonitor: failed to create CGEventTap (Accessibility may be denied)")
            Unmanaged<KeyMonitor>.fromOpaque(selfPtr).release()
            self.retainedSelfPtr = nil
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
        if let ptr = retainedSelfPtr {
            Unmanaged<KeyMonitor>.fromOpaque(ptr).release()
            retainedSelfPtr = nil
        }
        startedAt = nil
        Log.debug("KeyMonitor: tap removed")
    }

    /// Called from the CGEventTap callback. Returns true if event should be consumed.
    func handle(keyCode: Int64, cmdHeld: Bool = false) -> Bool {
        let tabKey: Int64 = 48
        let escKey: Int64 = 53
        let returnKey: Int64 = 36
        let spaceKey: Int64 = 49
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
        case spaceKey:
            if onSpace != nil {
                DispatchQueue.main.async { [weak self] in self?.onSpace?() }
                return true
            }
            return false
        case returnKey:
            if cmdHeld {
                if onCommandReturn != nil {
                    DispatchQueue.main.async { [weak self] in self?.onCommandReturn?() }
                    return true
                }
            } else {
                if onReturn != nil {
                    DispatchQueue.main.async { [weak self] in self?.onReturn?() }
                    return true
                }
            }
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
    let flags = event.flags
    let cmdHeld = flags.contains(.maskCommand)
    let consume = monitor.handle(keyCode: keyCode, cmdHeld: cmdHeld)
    return consume ? nil : Unmanaged.passUnretained(event)
}
