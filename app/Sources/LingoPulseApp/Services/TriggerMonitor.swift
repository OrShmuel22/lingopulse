import AppKit

// NSEvent global monitors always deliver on the main thread (main RunLoop),
// so @MainActor state can be accessed directly without extra Task hops.
@MainActor
final class TriggerMonitor {

    enum SingleKey { case rightCommand, rightOption, fn }
    enum DoubleTapMod { case shift, command, option }

    private var stateMachine: TriggerStateMachine
    private let onSingleKey: () -> Void
    private let onDoubleTap: () -> Void

    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    init(onSingleKey: @escaping () -> Void,
         onDoubleTap: @escaping () -> Void,
         singleKey: SingleKey = .rightCommand,
         doubleTapModifier: DoubleTapMod = .shift,
         singleKeyMaxHoldMs: Int = 250,
         doubleTapWindowMs: Int = 300) {
        self.onSingleKey = onSingleKey
        self.onDoubleTap = onDoubleTap
        self.stateMachine = TriggerStateMachine(
            singleKey: singleKey,
            doubleTapModifier: doubleTapModifier,
            singleKeyMaxHoldMs: singleKeyMaxHoldMs,
            doubleTapWindowMs: doubleTapWindowMs
        )
    }

    deinit {
        MainActor.assumeIsolated { stop() }
    }

    func start() {
        guard globalFlagsMonitor == nil else { return }

        let flagsMask: NSEvent.EventTypeMask = .flagsChanged
        let keyMask: NSEvent.EventTypeMask = .keyDown

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: flagsMask) { [weak self] event in
            self?.handleFlags(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: flagsMask) { [weak self] event in
            self?.handleFlags(event)
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: keyMask) { [weak self] event in
            self?.handleKeyDown(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: keyMask) { [weak self] event in
            self?.handleKeyDown(event)
            return event
        }
    }

    func stop() {
        if let m = globalFlagsMonitor { NSEvent.removeMonitor(m) }
        if let m = localFlagsMonitor  { NSEvent.removeMonitor(m) }
        if let m = globalKeyMonitor   { NSEvent.removeMonitor(m) }
        if let m = localKeyMonitor    { NSEvent.removeMonitor(m) }
        globalFlagsMonitor = nil
        localFlagsMonitor  = nil
        globalKeyMonitor   = nil
        localKeyMonitor    = nil
        stateMachine.reset()
    }

    private func handleFlags(_ event: NSEvent) {
        let tsMs = UInt64(event.timestamp * 1000)
        let smEvent: TriggerStateMachine.Event
        // .flagsChanged fires on both press and release; distinguish by whether
        // the relevant modifier bit is now set (press) or cleared (release).
        let flags = event.modifierFlags
        let kc = event.keyCode
        if TriggerStateMachine.isModifierDown(keyCode: kc, flags: flags) {
            smEvent = .modifierDown(keyCode: kc, modifiers: flags, timestampMs: tsMs)
        } else {
            smEvent = .modifierUp(keyCode: kc, modifiers: flags, timestampMs: tsMs)
        }
        let output = stateMachine.handle(smEvent)
        dispatch(output)
    }

    private func handleKeyDown(_ event: NSEvent) {
        let tsMs = UInt64(event.timestamp * 1000)
        let output = stateMachine.handle(.otherKeyDown(timestampMs: tsMs))
        dispatch(output)
    }

    private func dispatch(_ output: TriggerStateMachine.Output) {
        switch output {
        case .none: break
        case .singleKey: onSingleKey()
        case .doubleTap: onDoubleTap()
        }
    }
}

// MARK: - State machine (internal for testing)

struct TriggerStateMachine {
    enum Event {
        case modifierDown(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, timestampMs: UInt64)
        case modifierUp(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, timestampMs: UInt64)
        case otherKeyDown(timestampMs: UInt64)
    }
    enum Output { case none, singleKey, doubleTap }

    var singleKey: TriggerMonitor.SingleKey
    var doubleTapModifier: TriggerMonitor.DoubleTapMod
    var singleKeyMaxHoldMs: Int
    var doubleTapWindowMs: Int

    // Single-key state
    private var singleArmed = false
    private var singlePressTs: UInt64 = 0

    // Double-tap state
    private var doubleTapPhase: DoubleTapPhase = .idle

    init(singleKey: TriggerMonitor.SingleKey,
         doubleTapModifier: TriggerMonitor.DoubleTapMod,
         singleKeyMaxHoldMs: Int,
         doubleTapWindowMs: Int) {
        self.singleKey = singleKey
        self.doubleTapModifier = doubleTapModifier
        self.singleKeyMaxHoldMs = singleKeyMaxHoldMs
        self.doubleTapWindowMs = doubleTapWindowMs
    }

    private enum DoubleTapPhase {
        case idle
        // ⇧ is currently held (press time recorded); dirty = another key fired
        case held(pressTs: UInt64, dirty: Bool)
        // First clean tap completed; first-release timestamp for window check
        case firstTapDone(releaseTs: UInt64)
        // Second tap is now held
        case secondHeld(firstReleaseTs: UInt64, pressTs: UInt64, dirty: Bool)
    }

    mutating func reset() {
        singleArmed = false
        singlePressTs = 0
        doubleTapPhase = .idle
    }

    mutating func handle(_ event: Event) -> Output {
        switch event {
        case let .modifierDown(kc, flags, ts):
            return handleDown(keyCode: kc, flags: flags, ts: ts)
        case let .modifierUp(kc, flags, ts):
            return handleUp(keyCode: kc, flags: flags, ts: ts)
        case let .otherKeyDown(ts):
            return handleOtherKey(ts: ts)
        }
    }

    // MARK: - Key code constants
    // keyCode 54 = right ⌘ (left ⌘ is 55; Apple's left/right are swapped vs common docs)
    static let kcRightCommand: UInt16 = 54
    // keyCode 61 = right ⌥ (left ⌥ is 58)
    static let kcRightOption: UInt16 = 61
    // keyCode 63 = fn
    static let kcFn: UInt16 = 63
    // ⇧: left = 56, right = 60
    static let kcLeftShift: UInt16  = 56
    static let kcRightShift: UInt16 = 60
    // ⌘: left = 55, right = 54
    static let kcLeftCommand: UInt16  = 55
    // ⌥: left = 58, right = 61
    static let kcLeftOption: UInt16   = 58

    // Determine if the keyCode represents a modifier "press" (flag now set) vs "release".
    // For flagsChanged events: presence of the relevant flag means the key just went down.
    static func isModifierDown(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case kcRightCommand, kcLeftCommand: return flags.contains(.command)
        case kcRightOption, kcLeftOption:   return flags.contains(.option)
        case kcLeftShift, kcRightShift:     return flags.contains(.shift)
        case kcFn:                          return flags.contains(.function)
        default:                            return false
        }
    }

    // MARK: - Single-key target key code

    private var targetSingleKeyCode: UInt16 {
        switch singleKey {
        case .rightCommand: return Self.kcRightCommand
        case .rightOption:  return Self.kcRightOption
        case .fn:           return Self.kcFn
        }
    }

    // MARK: - Double-tap target key codes

    private func isDoubleTapKey(_ kc: UInt16) -> Bool {
        switch doubleTapModifier {
        case .shift:   return kc == Self.kcLeftShift || kc == Self.kcRightShift
        case .command: return kc == Self.kcLeftCommand || kc == Self.kcRightCommand
        case .option:  return kc == Self.kcLeftOption || kc == Self.kcRightOption
        }
    }

    // MARK: - Event handlers

    private mutating func handleDown(keyCode kc: UInt16, flags: NSEvent.ModifierFlags, ts: UInt64) -> Output {
        // Single-key: arm on target key down
        if kc == targetSingleKeyCode {
            singleArmed = true
            singlePressTs = ts
        }

        // Double-tap: track press
        if isDoubleTapKey(kc) {
            switch doubleTapPhase {
            case .idle:
                doubleTapPhase = .held(pressTs: ts, dirty: false)
            case .firstTapDone(let releaseTs):
                // Start second tap if within window
                if ts - releaseTs <= UInt64(doubleTapWindowMs) {
                    doubleTapPhase = .secondHeld(firstReleaseTs: releaseTs, pressTs: ts, dirty: false)
                } else {
                    // Window expired — first tap is stale; begin a new first tap
                    doubleTapPhase = .held(pressTs: ts, dirty: false)
                }
            case .held, .secondHeld:
                // Already held (repeat event?) — ignore
                break
            }
        }

        return .none
    }

    private mutating func handleUp(keyCode kc: UInt16, flags: NSEvent.ModifierFlags, ts: UInt64) -> Output {
        var output: Output = .none

        // Single-key: fire if armed and held within time limit
        if kc == targetSingleKeyCode {
            if singleArmed && (ts - singlePressTs) <= UInt64(singleKeyMaxHoldMs) {
                output = .singleKey
            }
            singleArmed = false
        }

        // Double-tap: track release
        if isDoubleTapKey(kc) {
            switch doubleTapPhase {
            case .held(_, let dirty):
                if dirty {
                    // Dirty tap — discard; start fresh next press
                    doubleTapPhase = .idle
                } else {
                    doubleTapPhase = .firstTapDone(releaseTs: ts)
                }
            case .secondHeld(_, _, let dirty):
                if dirty {
                    // Dirty second tap — discard both; go idle
                    doubleTapPhase = .idle
                } else {
                    // Clean second tap completed → fire
                    doubleTapPhase = .idle
                    output = .doubleTap
                }
            case .idle, .firstTapDone:
                break
            }
        }

        return output
    }

    private mutating func handleOtherKey(ts: UInt64) -> Output {
        // Cancel single-key tap
        singleArmed = false

        // Mark current double-tap held phase as dirty
        switch doubleTapPhase {
        case .held(let pressTs, _):
            doubleTapPhase = .held(pressTs: pressTs, dirty: true)
        case .secondHeld(let releaseTs, let pressTs, _):
            doubleTapPhase = .secondHeld(firstReleaseTs: releaseTs, pressTs: pressTs, dirty: true)
        default:
            break
        }

        return .none
    }
}
