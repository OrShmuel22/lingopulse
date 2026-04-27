import Testing
import AppKit
@testable import LingoPulseApp

@Suite struct TriggerMonitorTests {

    // MARK: - Helpers

    private func makeSM(
        singleKey: TriggerMonitor.SingleKey = .rightCommand,
        doubleTapModifier: TriggerMonitor.DoubleTapMod = .shift,
        singleKeyMaxHoldMs: Int = 250,
        doubleTapWindowMs: Int = 300
    ) -> TriggerStateMachine {
        TriggerStateMachine(
            singleKey: singleKey,
            doubleTapModifier: doubleTapModifier,
            singleKeyMaxHoldMs: singleKeyMaxHoldMs,
            doubleTapWindowMs: doubleTapWindowMs
        )
    }

    private func rightCmdDown(ts: UInt64) -> TriggerStateMachine.Event {
        .modifierDown(keyCode: 54, modifiers: .command, timestampMs: ts)
    }
    private func rightCmdUp(ts: UInt64) -> TriggerStateMachine.Event {
        .modifierUp(keyCode: 54, modifiers: [], timestampMs: ts)
    }
    private func leftShiftDown(ts: UInt64) -> TriggerStateMachine.Event {
        .modifierDown(keyCode: 56, modifiers: .shift, timestampMs: ts)
    }
    private func leftShiftUp(ts: UInt64) -> TriggerStateMachine.Event {
        .modifierUp(keyCode: 56, modifiers: [], timestampMs: ts)
    }

    // MARK: - Test 1: Clean right-⌘ tap within 100ms → .singleKey

    @Test func cleanRightCommandTap() {
        var sm = makeSM()
        _ = sm.handle(rightCmdDown(ts: 0))
        let out = sm.handle(rightCmdUp(ts: 100))
        #expect(out == .singleKey)
    }

    // MARK: - Test 2: Right-⌘ held 400ms (> 250ms limit) → .none

    @Test func rightCommandHeldTooLong() {
        var sm = makeSM()
        _ = sm.handle(rightCmdDown(ts: 0))
        let out = sm.handle(rightCmdUp(ts: 400))
        #expect(out == .none)
    }

    // MARK: - Test 3: Right-⌘ down → other keyDown → up → .none (dirty)

    @Test func rightCommandDirtyTap() {
        var sm = makeSM()
        _ = sm.handle(rightCmdDown(ts: 0))
        _ = sm.handle(.otherKeyDown(timestampMs: 50))
        let out = sm.handle(rightCmdUp(ts: 100))
        #expect(out == .none)
    }

    // MARK: - Test 4: Left ⌘ tap (keyCode 55) → .none (only right ⌘ counts)

    @Test func leftCommandTapIgnored() {
        var sm = makeSM(singleKey: .rightCommand)
        _ = sm.handle(.modifierDown(keyCode: 55, modifiers: .command, timestampMs: 0))
        let out = sm.handle(.modifierUp(keyCode: 55, modifiers: [], timestampMs: 100))
        #expect(out == .none)
    }

    // MARK: - Test 5: Two clean ⇧ taps within 200ms → .doubleTap

    @Test func doubleShiftTapWithinWindow() {
        var sm = makeSM(doubleTapWindowMs: 300)
        _ = sm.handle(leftShiftDown(ts: 0))
        _ = sm.handle(leftShiftUp(ts: 50))
        _ = sm.handle(leftShiftDown(ts: 150))  // 100ms after first release
        let out = sm.handle(leftShiftUp(ts: 200))
        #expect(out == .doubleTap)
    }

    // MARK: - Test 6: Two clean ⇧ taps with 400ms gap → .none, second starts new first tap

    @Test func doubleShiftTapWindowExpired() {
        var sm = makeSM(doubleTapWindowMs: 300)
        // First tap
        _ = sm.handle(leftShiftDown(ts: 0))
        _ = sm.handle(leftShiftUp(ts: 50))
        // Second tap starts 400ms after first release — window expired
        _ = sm.handle(leftShiftDown(ts: 450))
        let out = sm.handle(leftShiftUp(ts: 500))
        // Should be .none (no double tap) because the gap was too long
        #expect(out == .none)
    }

    // MARK: - Test 7: Dirty first ⇧ tap, then clean second → .none

    @Test func dirtyFirstTapThenCleanSecond() {
        var sm = makeSM(doubleTapWindowMs: 300)
        // First tap: dirty (another key fired while held)
        _ = sm.handle(leftShiftDown(ts: 0))
        _ = sm.handle(.otherKeyDown(timestampMs: 25))
        _ = sm.handle(leftShiftUp(ts: 50))
        // Second tap clean, within window of first release
        _ = sm.handle(leftShiftDown(ts: 150))
        let out = sm.handle(leftShiftUp(ts: 200))
        // First was dirty → became fresh "first tap" candidate only on the second press,
        // but that second press is now the new first tap, so no double yet
        #expect(out == .none)
    }

    // MARK: - Test 8: singleKey = .rightOption makes keyCode 61 fire .singleKey, 54 silent

    @Test func rightOptionSingleKey() {
        var sm = makeSM(singleKey: .rightOption)
        // Right option (keyCode 61) should fire
        _ = sm.handle(.modifierDown(keyCode: 61, modifiers: .option, timestampMs: 0))
        let outOption = sm.handle(.modifierUp(keyCode: 61, modifiers: [], timestampMs: 100))
        #expect(outOption == .singleKey)

        // Right command (keyCode 54) should be silent
        _ = sm.handle(.modifierDown(keyCode: 54, modifiers: .command, timestampMs: 200))
        let outCmd = sm.handle(.modifierUp(keyCode: 54, modifiers: [], timestampMs: 250))
        #expect(outCmd == .none)
    }
}
