import Testing
@testable import LingoPulseApp

@Suite struct KeyMonitorHandleTests {
    @Test func tabIsConsumed() {
        let m = KeyMonitor()
        #expect(m.handle(keyCode: 48) == true)  // Tab consumed
    }

    @Test func escIsConsumed() {
        let m = KeyMonitor()
        #expect(m.handle(keyCode: 53) == true)  // Esc
    }

    @Test func arrowDownConsumed() {
        let m = KeyMonitor()
        #expect(m.handle(keyCode: 125) == true)
    }

    @Test func arrowUpConsumed() {
        let m = KeyMonitor()
        #expect(m.handle(keyCode: 126) == true)
    }

    @Test func returnPassedThroughWhenNoCallback() {
        let m = KeyMonitor()
        #expect(m.handle(keyCode: 36) == false)  // Return with no onReturn set
    }

    @Test func returnConsumedWhenCallbackSet() {
        let m = KeyMonitor()
        m.onReturn = {}
        #expect(m.handle(keyCode: 36) == true)
    }

    @Test func cmdReturnConsumedWhenCallbackSet() {
        let m = KeyMonitor()
        m.onCommandReturn = {}
        #expect(m.handle(keyCode: 36, cmdHeld: true) == true)
    }

    @Test func cmdReturnPassedThroughWhenNoCallback() {
        let m = KeyMonitor()
        #expect(m.handle(keyCode: 36, cmdHeld: true) == false)
    }

    @Test func spaceConsumedWhenCallbackSet() {
        let m = KeyMonitor()
        m.onSpace = {}
        #expect(m.handle(keyCode: 49) == true)
    }

    @Test func spacePassedThroughWhenNoCallback() {
        let m = KeyMonitor()
        #expect(m.handle(keyCode: 49) == false)
    }

    @Test func letterPassedThrough() {
        let m = KeyMonitor()
        // Without start(), startedAt is nil so grace check is skipped — falls through to false.
        #expect(m.handle(keyCode: 0) == false)  // 'a'
    }
}
