import Testing
import Foundation
@testable import LingoPulseApp

@Suite struct DebouncerTests {
    @Test func firesAfterInterval() async {
        let bgQueue = DispatchQueue(label: "debouncer-test")
        let debouncer = Debouncer(interval: 0.05, queue: bgQueue)
        await confirmation("fired") { c in
            debouncer.schedule { c() }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    @Test func cancelsPriorOnReschedule() async {
        let bgQueue = DispatchQueue(label: "debouncer-test-cancel")
        let debouncer = Debouncer(interval: 0.05, queue: bgQueue)
        await confirmation("second only", expectedCount: 1) { c in
            debouncer.schedule { Issue.record("first should be cancelled") }
            debouncer.schedule { c() }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    @Test func cancelStopsFire() async {
        let bgQueue = DispatchQueue(label: "debouncer-test-stop")
        let debouncer = Debouncer(interval: 0.05, queue: bgQueue)
        await confirmation("did not fire", expectedCount: 0) { c in
            debouncer.schedule { c() }
            debouncer.cancel()
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }
}
