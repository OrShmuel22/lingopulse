import Testing
import Foundation
@testable import LingoPulseApp

// Verifies that Fixer.refine does not crash on a 5000-character input and that the full
// text is forwarded to Ollama unmodified (no silent truncation).
// Design choice: no length cap is added. The text is sent in full; callers that hit
// model context limits will receive a gracefully degraded response or a timeout, both
// of which are already handled by Fixer. A cap would require a visible warning and was
// not chosen here — see spec Task #12.

private final class LongInputMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var capturedPrompt: String = ""

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 1 << 17)
            defer { buf.deallocate(); stream.close() }
            while stream.hasBytesAvailable {
                let n = stream.read(buf, maxLength: 1 << 17)
                if n <= 0 { break }
                body.append(buf, count: n)
            }
        }

        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let prompt = json["prompt"] as? String {
            LongInputMockURLProtocol.capturedPrompt = prompt
        }

        let url = request.url ?? URL(string: "http://127.0.0.1")!
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        // Echo back a fixed refined string so Fixer can complete without error.
        let responseJSON = try! JSONSerialization.data(withJSONObject: ["response": "Refined output."])
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseJSON)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct LongInputSafetyTests {

    @Test @MainActor func fiveThousandCharInputSentUnmodified() async throws {
        let longText = String(repeating: "a", count: 5000)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LongInputMockURLProtocol.self]
        LongInputMockURLProtocol.capturedPrompt = ""
        let session = URLSession(configuration: config)

        let ollama = OllamaService(session: session)
        let appConfig = AppConfig(configURL: URL(fileURLWithPath: "/dev/null/nonexistent"))
        let ring = RingBuffer(
            fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("long-ring-\(UUID().uuidString).json"),
            size: 5
        )
        let history = HistoryStore(
            fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("long-hist-\(UUID().uuidString).jsonl")
        )
        let fixer = Fixer(ollama: ollama, config: appConfig, history: history, ring: ring)

        // Must not throw or crash
        let result = try await fixer.refine(selection: longText, app: "TestApp")
        #expect(result.original == longText)
        #expect(!result.refined.isEmpty)

        // The 5000-char input must appear verbatim in the prompt sent to Ollama.
        // (Protection may replace URLs/emails but "aaa...a" has none, so it passes through intact.)
        #expect(LongInputMockURLProtocol.capturedPrompt.contains(longText),
                "Ollama prompt must contain the full 5000-char input unmodified")
    }
}
