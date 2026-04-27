import Testing
import Foundation
@testable import LingoPulseApp

final class FixerMockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = FixerMockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (resp, data) = try handler(request)
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

// MARK: - Helpers

@MainActor
private func makeFixer(ollamaResponse: String) -> (Fixer, RingBuffer, HistoryStore) {
    let session = makeMockSessionForFixer(response: ollamaResponse)
    let ollama = OllamaService(session: session)
    let config = AppConfig(configURL: URL(fileURLWithPath: "/dev/null/nonexistent"))
    let ringURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fixer-ring-\(UUID().uuidString).json")
    let histURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("fixer-hist-\(UUID().uuidString).jsonl")
    let ring = RingBuffer(fileURL: ringURL, size: 5)
    let history = HistoryStore(fileURL: histURL)
    let fixer = Fixer(ollama: ollama, config: config, history: history, ring: ring)
    return (fixer, ring, history)
}

private func makeMockSessionForFixer(response: String) -> URLSession {
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

// MARK: - SpellCheck stub for Fixer integration test

private final class StubSpellCheck: SpellChecking {
    var capturedText: String = ""
    let edit: SpellCorrection

    init(original: String, corrected: String) {
        self.edit = SpellCorrection(
            original: original,
            corrected: corrected,
            nsRange: NSRange(location: 0, length: (original as NSString).length)
        )
    }

    func correct(_ text: String) -> (corrected: String, edits: [SpellCorrection]) {
        capturedText = text
        let result = text.replacingOccurrences(of: edit.original, with: edit.corrected)
        let changed = result != text
        return (result, changed ? [edit] : [])
    }
}

// MARK: - Tests

@Suite(.serialized) struct FixerTests {

    @Test @MainActor func emptySelectionThrows() async throws {
        let (fixer, _, _) = makeFixer(ollamaResponse: "irrelevant")
        await #expect(throws: FixerError.emptySelection) {
            try await fixer.refine(selection: "   ", app: "Slack")
        }
    }

    @Test @MainActor func roundTripRefine() async throws {
        let (fixer, ring, history) = makeFixer(ollamaResponse: "Hello, world.")

        let result = try await fixer.refine(selection: "hello world", app: "Slack")

        #expect(result.original == "hello world")
        #expect(result.refined == "Hello, world.")
        #expect(result.app == "Slack")

        let ringEntries = try await ring.listAll()
        #expect(ringEntries.count == 1)
        #expect(ringEntries[0]["original"] as? String == "hello world")
        #expect(ringEntries[0]["refined"] as? String == "Hello, world.")

        let histEntries = try await history.readAll()
        #expect(histEntries.count == 1)
        #expect(histEntries[0]["mode"] as? String == "fixer_refine")
        #expect(histEntries[0]["refined"] as? String == "Hello, world.")
    }

    @Test @MainActor func alreadyRefinedReturnsTrueWithinWindow() async throws {
        let (fixer, ring, _) = makeFixer(ollamaResponse: "irrelevant")

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let recentTs = fmt.string(from: Date())

        try await ring.append([
            "original": "hello world",
            "refined": "Hello, world.",
            "app": "Slack",
            "timestamp": recentTs,
        ])

        let result = await fixer.alreadyRefined("Hello, world.")
        #expect(result == true)
    }

    @Test @MainActor func alreadyRefinedReturnsFalseForOldTimestamp() async throws {
        let (fixer, ring, _) = makeFixer(ollamaResponse: "irrelevant")

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let oldTs = fmt.string(from: Date().addingTimeInterval(-60))

        try await ring.append([
            "original": "hello world",
            "refined": "Hello, world.",
            "app": "Slack",
            "timestamp": oldTs,
        ])

        let result = await fixer.alreadyRefined("Hello, world.")
        #expect(result == false)
    }

    @Test @MainActor func spellCheckPrePassSendsCorrectWordToOllama() async throws {
        // Verify that when a SpellChecking instance corrects a word, the prompt
        // sent to Ollama contains the corrected word, not the original typo.
        var capturedPrompt: String = ""
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [FixerMockURLProtocol.self]
        FixerMockURLProtocol.handler = { req in
            let httpResp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            var body = req.httpBody ?? Data()
            if body.isEmpty, let stream = req.httpBodyStream {
                stream.open()
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
                defer { buf.deallocate(); stream.close() }
                while stream.hasBytesAvailable {
                    let n = stream.read(buf, maxLength: 65536)
                    if n <= 0 { break }
                    body.append(buf, count: n)
                }
            }
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let prompt = json["prompt"] as? String {
                capturedPrompt = prompt
            }
            return (httpResp, try! JSONSerialization.data(withJSONObject: ["response": "fixed text"]))
        }

        let stub = StubSpellCheck(original: "beacuse", corrected: "because")
        let ollama = OllamaService(session: URLSession(configuration: sessionConfig))
        let config = AppConfig(configURL: URL(fileURLWithPath: "/dev/null/nonexistent"))
        let ring = RingBuffer(
            fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("fixer-ring-\(UUID().uuidString).json"),
            size: 5
        )
        let history = HistoryStore(
            fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("fixer-hist-\(UUID().uuidString).jsonl")
        )
        let fixer = Fixer(ollama: ollama, config: config, history: history, ring: ring, spellCheck: stub)

        _ = try await fixer.refine(selection: "beacuse", app: "Slack")

        #expect(capturedPrompt.contains("because"))
        #expect(!capturedPrompt.contains("beacuse"))
    }

    @Test @MainActor func protectionRoundTripRestoresURL() async throws {
        let url = "https://example.com/x"
        // Input without URLs so Protection produces no tokens — mock returns a corrected version
        // that still contains the URL verbatim, verifying the restore path handles zero tokens.
        let input = "check out https://example.com/x for info"

        // The mock returns the same text with a minor prose fix; the URL must survive unchanged.
        // Because Protection redacts the URL into a placeholder, the mock must echo that placeholder
        // back. We capture it by intercepting the actual Ollama request body inside the mock.
        var capturedPrompt: String = ""
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [FixerMockURLProtocol.self]
        FixerMockURLProtocol.handler = { req in
            let httpResp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            var body = req.httpBody ?? Data()
            if body.isEmpty, let stream = req.httpBodyStream {
                stream.open()
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
                defer { buf.deallocate(); stream.close() }
                while stream.hasBytesAvailable {
                    let n = stream.read(buf, maxLength: 65536)
                    if n <= 0 { break }
                    body.append(buf, count: n)
                }
            }
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let prompt = json["prompt"] as? String {
                capturedPrompt = prompt
            }
            // Extract the redacted prompt text (after "Input:  " line) and echo it back
            // so restore() gets the exact placeholder the fixer used.
            let lines = capturedPrompt.components(separatedBy: "\n")
            let inputLine = lines.last(where: { $0.hasPrefix("Input:") }) ?? ""
            let redacted = inputLine.replacingOccurrences(of: "Input:  ", with: "").trimmingCharacters(in: .whitespaces)
            let responseText = redacted.isEmpty ? capturedPrompt : redacted
            let json2 = ["response": responseText]
            let data = try! JSONSerialization.data(withJSONObject: json2)
            return (httpResp, data)
        }
        let sess = URLSession(configuration: sessionConfig)

        let ollama = OllamaService(session: sess)
        let config = AppConfig(configURL: URL(fileURLWithPath: "/dev/null/nonexistent"))
        let ring = RingBuffer(
            fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("fixer-ring-\(UUID().uuidString).json"),
            size: 5
        )
        let history = HistoryStore(
            fileURL: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("fixer-hist-\(UUID().uuidString).jsonl")
        )
        let fixer = Fixer(ollama: ollama, config: config, history: history, ring: ring)

        let result = try await fixer.refine(selection: input, app: "Chrome")
        #expect(result.refined.contains(url))
    }
}
