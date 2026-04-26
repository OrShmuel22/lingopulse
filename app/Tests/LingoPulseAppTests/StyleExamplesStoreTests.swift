import Testing
import Foundation
@testable import LingoPulseApp

@Suite struct StyleExamplesStoreTests {
    private func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("style-\(UUID().uuidString).jsonl")
    }

    @Test func appendAndReadAll() async throws {
        let store = StyleExamplesStore(fileURL: tempURL())
        try await store.append(["text": "Great prose example", "app": "Notes"])

        let all = try await store.readAll()
        #expect(all.count == 1)
        #expect(all[0]["text"] as? String == "Great prose example")
        #expect(all[0]["app"] as? String == "Notes")
    }

    @Test func injectTimestamp() async throws {
        let store = StyleExamplesStore(fileURL: tempURL())
        let before = Date()
        try await store.append(["text": "no-ts", "app": "Safari"])
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

    @Test func preserveExplicitTimestamp() async throws {
        let store = StyleExamplesStore(fileURL: tempURL())
        let explicit = "2025-06-15T10:30:00+05:00"
        try await store.append(["text": "ts-set", "app": "Xcode", "timestamp": explicit])

        let all = try await store.readAll()
        #expect(all[0]["timestamp"] as? String == explicit)
    }
}
