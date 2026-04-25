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

    @Test func returnPassedThrough() {
        let m = KeyMonitor()
        #expect(m.handle(keyCode: 36) == false)  // Return
    }

    @Test func letterPassedThrough() {
        let m = KeyMonitor()
        // Without start(), startedAt is nil so grace check is skipped — falls through to false.
        #expect(m.handle(keyCode: 0) == false)  // 'a'
    }
}
