import Testing
import Foundation
@testable import LingoPulseApp

@MainActor
private func makeFixer(ollamaResponse: String) -> Fixer {
    let session = makeMockSession(response: ollamaResponse)
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

private func makeMockSession(response: String) -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FixerMockURLProtocol.self]
    FixerMockURLProtocol.handler = { req in
        let url = req.url ?? URL(string: "http://127.0.0.1")!
        let httpResp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let json = ["response": response]
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
            showPreview: { _, _, _ in previewCalls += 1 }
        )
        await cmd.execute()

        #expect(tonePickCalls == 0)
        #expect(previewCalls == 0)
        let entries = try await fixer.ring.listAll()
        #expect(entries.isEmpty)
    }

    @Test @MainActor func whitespaceOnlyCaptureReturnsEarly() async throws {
        let fixer = makeFixer(ollamaResponse: "should not be called")
        var tonePickCalls = 0

        let cmd = QuickRefineCommand(
            fixer: fixer,
            capture: { "   \n  " },
            tonePick: { tonePickCalls += 1; return "Neutral" },
            showPreview: { _, _, _ in }
        )
        await cmd.execute()

        #expect(tonePickCalls == 0)
        let entries = try await fixer.ring.listAll()
        #expect(entries.isEmpty)
    }

    @Test @MainActor func toneCancelledSkipsRefine() async throws {
        let fixer = makeFixer(ollamaResponse: "should not be called")
        var previewCalls = 0

        let cmd = QuickRefineCommand(
            fixer: fixer,
            capture: { "fix this typo" },
            tonePick: { nil },
            showPreview: { _, _, _ in previewCalls += 1 }
        )
        await cmd.execute()

        #expect(previewCalls == 0)
        let entries = try await fixer.ring.listAll()
        #expect(entries.isEmpty)
    }

    @Test @MainActor func happyPathRefinesAndShowsPreview() async throws {
        let fixer = makeFixer(ollamaResponse: "Fix this typo.")
        var previewArgs: FixerResult?

        let cmd = QuickRefineCommand(
            fixer: fixer,
            capture: { "fix this typo" },
            tonePick: { "Grammar-only" },
            showPreview: { result, _, _ in previewArgs = result }
        )
        await cmd.execute()

        #expect(previewArgs?.refined == "Fix this typo.")
        #expect(previewArgs?.app == Constants.AppNames.quickRefine)
        let entries = try await fixer.ring.listAll()
        #expect(entries.count == 1)
    }

    @Test @MainActor func rejectCallbackPopsRingEntry() async throws {
        let fixer = makeFixer(ollamaResponse: "Fix this typo.")
        var capturedReject: (() -> Void)?

        let cmd = QuickRefineCommand(
            fixer: fixer,
            capture: { "fix this typo" },
            tonePick: { "Grammar-only" },
            showPreview: { _, _, reject in capturedReject = reject }
        )
        await cmd.execute()

        let beforeReject = try await fixer.ring.listAll()
        #expect(beforeReject.count == 1)

        capturedReject?()
        // popLatest() runs in a Task; give it a tick.
        try await Task.sleep(for: .milliseconds(50))

        let afterReject = try await fixer.ring.listAll()
        #expect(afterReject.isEmpty)
    }
}
