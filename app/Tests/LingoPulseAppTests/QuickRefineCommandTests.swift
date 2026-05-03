import Testing
import Foundation
@testable import LingoPulseApp

@MainActor
private func makeFixer(ollamaResponses: [String]) -> Fixer {
    let session = makeMockSession(responses: ollamaResponses)
    let ollama = OllamaService(session: session)
    let config = AppConfig(configURL: URL(fileURLWithPath: "/dev/null/nonexistent"))
    let ring = RingBuffer(
        fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quickrefine-ring-\(UUID().uuidString).json"),
        size: 5
    )
    let history = HistoryStore(
        fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quickrefine-hist-\(UUID().uuidString).jsonl")
    )
    return Fixer(ollama: ollama, config: config, history: history, ring: ring)
}

@MainActor
private func makeFixer(ollamaResponse: String) -> Fixer {
    makeFixer(ollamaResponses: [ollamaResponse])
}

private final class ResponseQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String]
    init(_ responses: [String]) { self.responses = responses }
    func next() -> String {
        lock.lock(); defer { lock.unlock() }
        guard !responses.isEmpty else { return "" }
        return responses.removeFirst()
    }
}

private func makeMockSession(responses: [String]) -> URLSession {
    let queue = ResponseQueue(responses)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FixerMockURLProtocol.self]
    FixerMockURLProtocol.handler = { req in
        let url = req.url ?? URL(string: "http://127.0.0.1")!
        let httpResp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let json = ["response": queue.next()]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return (httpResp, data)
    }
    return URLSession(configuration: config)
}

@Suite(.serialized) struct QuickRefineCommandTests {

    @Test @MainActor func emptyCaptureReturnsEarly() async throws {
        let fixer = makeFixer(ollamaResponse: "should not be called")
        var tonePickCalls = 0
        var previewCalls = 0

        let cmd = QuickRefineCommand(
            fixer: fixer,
            capture: { nil },
            tonePick: { tonePickCalls += 1; return "Neutral" },
            showPreview: { _, _ in previewCalls += 1 }
        )
        await cmd.execute()

        #expect(tonePickCalls == 0)
        #expect(previewCalls == 0)
        let entries = try await fixer.ring.listAll()
        #expect(entries.isEmpty)
    }

    @Test @MainActor func whitespaceOnlyCaptureReturnsEarly() async throws {
        let fixer = makeFixer(ollamaResponse: "should not be called")
        var previewCalls = 0

        let cmd = QuickRefineCommand(
            fixer: fixer,
            capture: { "   \n  " },
            tonePick: { "Neutral" },
            showPreview: { _, _ in previewCalls += 1 }
        )
        await cmd.execute()

        #expect(previewCalls == 0)
        let entries = try await fixer.ring.listAll()
        #expect(entries.isEmpty)
    }

    // Default flow: capture → refine with default tone (Grammar-only) → preview.
    // Tone picker is NOT invoked unless the user presses T from preview.
    @Test @MainActor func happyPathSkipsTonePickerAndShowsPreview() async throws {
        let fixer = makeFixer(ollamaResponse: "Fix this typo.")
        var tonePickCalls = 0
        var previewArgs: FixerResult?

        let cmd = QuickRefineCommand(
            fixer: fixer,
            capture: { "fix this typo" },
            tonePick: { tonePickCalls += 1; return "Casual" },
            showPreview: { result, onOutcome in
                previewArgs = result
                onOutcome(.accepted)
            }
        )
        await cmd.execute()

        #expect(tonePickCalls == 0)  // Default flow does NOT open tone picker.
        #expect(previewArgs?.refined == "Fix this typo.")
        #expect(previewArgs?.app == Constants.AppNames.quickRefine)
        let entries = try await fixer.ring.listAll()
        #expect(entries.count == 1)
    }

    @Test @MainActor func rejectOutcomePopsRingEntry() async throws {
        let fixer = makeFixer(ollamaResponse: "Fix this typo.")

        let cmd = QuickRefineCommand(
            fixer: fixer,
            capture: { "fix this typo" },
            tonePick: { nil },
            showPreview: { _, onOutcome in onOutcome(.rejected) }
        )
        await cmd.execute()

        // popLatest() runs in a Task; give it a tick.
        try await Task.sleep(for: .milliseconds(50))

        let entries = try await fixer.ring.listAll()
        #expect(entries.isEmpty)
    }

    // T pressed → tone picker opens → user picks new tone → re-refine with new
    // tone → final preview shown. Old ring entry is popped before re-refine so
    // history doesn't accumulate stale attempts.
    @Test @MainActor func changeToneRerefinesWithNewTone() async throws {
        let fixer = makeFixer(ollamaResponses: ["First refine.", "Second refine."])
        var previewCount = 0
        var lastResult: FixerResult?

        let cmd = QuickRefineCommand(
            fixer: fixer,
            capture: { "fix this typo" },
            tonePick: { "Casual" },
            showPreview: { result, onOutcome in
                previewCount += 1
                lastResult = result
                if previewCount == 1 {
                    onOutcome(.changeTone)
                } else {
                    onOutcome(.accepted)
                }
            }
        )
        await cmd.execute()

        #expect(previewCount == 2)
        #expect(lastResult?.refined == "Second refine.")
        let entries = try await fixer.ring.listAll()
        #expect(entries.count == 1)  // First entry was popped before re-refine.
    }

    // T pressed → tone picker cancelled (returns nil) → exit silently.
    // No second refine, ring entry from first refine was popped before tone pick.
    @Test @MainActor func changeToneCancelledExitsWithoutRerefine() async throws {
        let fixer = makeFixer(ollamaResponses: ["First refine."])
        var previewCount = 0

        let cmd = QuickRefineCommand(
            fixer: fixer,
            capture: { "fix this typo" },
            tonePick: { nil },
            showPreview: { _, onOutcome in
                previewCount += 1
                onOutcome(.changeTone)
            }
        )
        await cmd.execute()

        #expect(previewCount == 1)  // Preview shown only once.
        try await Task.sleep(for: .milliseconds(50))
        let entries = try await fixer.ring.listAll()
        #expect(entries.isEmpty)  // Entry popped when user pressed T.
    }
}
