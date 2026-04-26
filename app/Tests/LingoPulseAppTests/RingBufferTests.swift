import Testing
import Foundation
@testable import LingoPulseApp

@Suite struct RingBufferTests {
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ring-\(UUID().uuidString).json")
    }

    @Test func appendFillsAndEvictsOldest() async throws {
        let ring = RingBuffer(fileURL: tempURL(), size: 3)
        for i in 0..<4 {
            try await ring.append(["i": i])
        }

        let all = try await ring.listAll()
        #expect(all.count == 3)
        // newest-first: last appended (i=3) is first
        #expect(all[0]["i"] as? Int == 3)
        #expect(all[1]["i"] as? Int == 2)
        #expect(all[2]["i"] as? Int == 1)
    }

    @Test func popLatestReturnsLastAndRemovesIt() async throws {
        let ring = RingBuffer(fileURL: tempURL(), size: 5)
        try await ring.append(["i": 0])
        try await ring.append(["i": 1])

        let popped = try await ring.popLatest()
        #expect(popped?["i"] as? Int == 1)

        let remaining = try await ring.listAll()
        #expect(remaining.count == 1)
        #expect(remaining[0]["i"] as? Int == 0)
    }

    @Test func listAllReturnsNewestFirst() async throws {
        let ring = RingBuffer(fileURL: tempURL(), size: 5)
        try await ring.append(["i": 10])
        try await ring.append(["i": 20])
        try await ring.append(["i": 30])

        let all = try await ring.listAll()
        #expect(all.map { $0["i"] as? Int } == [30, 20, 10])
    }

    @Test func findMatchingReturnsFirstHitOrNil() async throws {
        let ring = RingBuffer(fileURL: tempURL(), size: 5)
        try await ring.append(["kind": "A", "val": 1])
        try await ring.append(["kind": "B", "val": 2])
        try await ring.append(["kind": "A", "val": 3])

        let found = try await ring.findMatching { $0["kind"] as? String == "A" }
        // newest-first: first "A" hit is val=3
        #expect(found?["val"] as? Int == 3)

        let notFound = try await ring.findMatching { $0["kind"] as? String == "Z" }
        #expect(notFound == nil)
    }

    @Test func popLatestOnEmptyReturnsNil() async throws {
        let url = tempURL()
        let ring = RingBuffer(fileURL: url, size: 5)
        let result = try await ring.popLatest()
        #expect(result == nil)
    }
}
