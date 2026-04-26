import Testing
import Foundation
@testable import LingoPulseApp

// MARK: - MockURLProtocol

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        // URLProtocol receives the body via httpBodyStream, not httpBody.
        // Reconstruct a request with httpBody set so handlers can read it normally.
        var requestWithBody = request
        if let stream = request.httpBodyStream {
            stream.open()
            var bodyData = Data()
            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: bufferSize)
                if n > 0 { bodyData.append(buffer, count: n) }
            }
            stream.close()
            requestWithBody.httpBody = bodyData
        }
        do {
            let (response, data) = try handler(requestWithBody)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

private func ollamaResponseData(_ text: String) -> Data {
    let json = ["response": text]
    return try! JSONSerialization.data(withJSONObject: json)
}

private func openaiResponseData(_ text: String) -> Data {
    let json: [String: Any] = [
        "choices": [["message": ["role": "assistant", "content": text]]]
    ]
    return try! JSONSerialization.data(withJSONObject: json)
}

private func ok200(url: URL) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
}

// MARK: - Tests

@Suite(.serialized) struct OllamaServiceTests {

    // MARK: 1. Ollama payload

    @Test @MainActor func ollamaPayloadKeys() async throws {
        let session = makeMockSession()
        var capturedRequest: URLRequest?

        MockURLProtocol.handler = { req in
            capturedRequest = req
            return (ok200(url: req.url!), ollamaResponseData("ok"))
        }

        let svc = OllamaService(backend: .ollama, host: "http://127.0.0.1:11434", session: session)
        _ = try await svc.generate(
            model: "gemma3:4b",
            prompt: "hello",
            keepAlive: "10m",
            format: "json",
            timeout: 5,
            think: true,
            options: ["temperature": 0.7]
        )

        let body = try #require(capturedRequest?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(capturedRequest?.url?.path == "/api/generate")
        #expect(json["model"] as? String == "gemma3:4b")
        #expect(json["prompt"] as? String == "hello")
        #expect(json["keep_alive"] as? String == "10m")
        #expect(json["stream"] as? Bool == false)
        #expect(json["think"] as? Bool == true)
        #expect(json["format"] as? String == "json")
        let opts = try #require(json["options"] as? [String: Any])
        #expect(opts["temperature"] as? Double == 0.7)
    }

    @Test @MainActor func ollamaPayloadOmitsFormatAndOptionsWhenAbsent() async throws {
        let session = makeMockSession()
        var capturedRequest: URLRequest?

        MockURLProtocol.handler = { req in
            capturedRequest = req
            return (ok200(url: req.url!), ollamaResponseData("ok"))
        }

        let svc = OllamaService(backend: .ollama, host: "http://127.0.0.1:11434", session: session)
        _ = try await svc.generate(model: "gemma3:4b", prompt: "hi")

        let body = try #require(capturedRequest?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["format"] == nil)
        #expect(json["options"] == nil)
    }

    // MARK: 2. OpenAI payload

    @Test @MainActor func openaiPayloadKeys() async throws {
        let session = makeMockSession()
        var capturedRequest: URLRequest?

        MockURLProtocol.handler = { req in
            capturedRequest = req
            return (ok200(url: req.url!), openaiResponseData("ok"))
        }

        let svc = OllamaService(backend: .openai, host: "http://127.0.0.1:11434", session: session)
        _ = try await svc.generate(model: "gpt-4o-mini", prompt: "hello", format: "json")

        let body = try #require(capturedRequest?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(capturedRequest?.url?.path == "/v1/chat/completions")
        #expect(json["model"] as? String == "gpt-4o-mini")
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
        #expect(messages[0]["content"] as? String == "hello")
        #expect(json["stream"] as? Bool == false)
        #expect(json["max_tokens"] as? Int == 2048)
        let fmt = try #require(json["response_format"] as? [String: Any])
        #expect(fmt["type"] as? String == "json_object")
    }

    @Test @MainActor func openaiPayloadOmitsResponseFormatWhenNotJson() async throws {
        let session = makeMockSession()
        var capturedRequest: URLRequest?

        MockURLProtocol.handler = { req in
            capturedRequest = req
            return (ok200(url: req.url!), openaiResponseData("ok"))
        }

        let svc = OllamaService(backend: .openai, host: "http://127.0.0.1:11434", session: session)
        _ = try await svc.generate(model: "gpt-4o-mini", prompt: "hi")

        let body = try #require(capturedRequest?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(json["response_format"] == nil)
    }

    // MARK: 3. Single-flight busy

    @Test @MainActor func secondConcurrentCallThrowsBusy() async throws {
        let session = makeMockSession()

        // Semaphore blocks the mock handler thread until we signal it from the test.
        let gate = DispatchSemaphore(value: 0)

        MockURLProtocol.handler = { req in
            gate.wait()
            return (ok200(url: req.url!), ollamaResponseData("done"))
        }

        let svc = OllamaService(backend: .ollama, host: "http://127.0.0.1:11434", session: session)

        // Fire first call (stays in flight while gate is closed)
        let first = Task { @MainActor in
            try await svc.generate(model: "m", prompt: "p")
        }

        // Give the first call time to start and set inFlight = true
        try await Task.sleep(nanoseconds: 50_000_000)

        // Second call should immediately get .busy
        var caughtError: OllamaError?
        do {
            _ = try await svc.generate(model: "m", prompt: "p2")
        } catch let e as OllamaError {
            caughtError = e
        }

        // Unblock first call and wait for it to finish
        gate.signal()
        _ = try? await first.value

        #expect(caughtError == .busy)
    }

    // MARK: 4. Timeout maps to .timeout

    @Test @MainActor func timeoutErrorMapsToOllamaTimeout() async throws {
        let session = makeMockSession()

        MockURLProtocol.handler = { _ in
            throw URLError(.timedOut)
        }

        let svc = OllamaService(backend: .ollama, host: "http://127.0.0.1:11434", session: session)

        var caughtError: OllamaError?
        do {
            _ = try await svc.generate(model: "m", prompt: "p", timeout: 1)
        } catch let e as OllamaError {
            caughtError = e
        }

        #expect(caughtError == .timeout)
    }

    // MARK: 5. HTTP non-2xx maps to .http(code)

    @Test @MainActor func http500MapsToOllamaHttpError() async throws {
        let session = makeMockSession()

        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }

        let svc = OllamaService(backend: .ollama, host: "http://127.0.0.1:11434", session: session)

        var caughtError: OllamaError?
        do {
            _ = try await svc.generate(model: "m", prompt: "p")
        } catch let e as OllamaError {
            caughtError = e
        }

        #expect(caughtError == .http(500))
    }
}
