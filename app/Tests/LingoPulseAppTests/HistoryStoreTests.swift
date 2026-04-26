import Testing
import Foundation
@testable import LingoPulseApp

@Suite struct HistoryStoreTests {
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hist-\(UUID().uuidString).jsonl")
    }

    @Test func appendAndReadAllRoundTrip() async throws {
        let store = HistoryStore(fileURL: tempURL())
        try await store.append(["text": "hello", "timestamp": "2026-01-01T00:00:00+00:00"])
        try await store.append(["text": "world", "timestamp": "2026-01-02T00:00:00+00:00"])

        let all = try await store.readAll()
        #expect(all.count == 2)
        #expect(all[0]["text"] as? String == "hello")
        #expect(all[1]["text"] as? String == "world")
    }

    @Test func autoInjectsTimestampWhenMissing() async throws {
        let store = HistoryStore(fileURL: tempURL())
        let before = Date()
        try await store.append(["text": "no-ts"])
        let after = Date()

        let all = try await store.readAll()
        #expect(all.count == 1)
        let tsString = all[0]["timestamp"] as? String
        #expect(tsString != nil)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let ts = tsString, let parsed = formatter.date(from: ts) {
            #expect(parsed >= before && parsed <= after)
        } else {
            Issue.record("timestamp missing or unparseable: \(tsString ?? "nil")")
        }
    }

    @Test func preservesExplicitTimestamp() async throws {
        let store = HistoryStore(fileURL: tempURL())
        let explicit = "2025-06-15T10:30:00+05:00"
        try await store.append(["text": "ts-set", "timestamp": explicit])

        let all = try await store.readAll()
        #expect(all[0]["timestamp"] as? String == explicit)
    }

    @Test func createsParentDirectory() async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("sub")
            .appendingPathComponent("hist.jsonl")

        let store = HistoryStore(fileURL: base)
        try await store.append(["text": "mkdir-test"])

        let all = try await store.readAll()
        #expect(all.count == 1)

        try? FileManager.default.removeItem(at: base.deletingLastPathComponent().deletingLastPathComponent())
    }
}
