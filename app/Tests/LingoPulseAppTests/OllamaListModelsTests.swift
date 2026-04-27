import Testing
import Foundation
@testable import LingoPulseApp

// Own URLProtocol subclass so we never share the handler static with MockURLProtocol
// (which OllamaServiceTests uses), eliminating the cross-suite race condition.
final class ListModelsURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = ListModelsURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
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

private func makeListModelsSession(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [ListModelsURLProtocol.self]
    ListModelsURLProtocol.handler = handler
    return URLSession(configuration: config)
}

private func tagsJSON(models: [[String: Any]]) -> Data {
    try! JSONSerialization.data(withJSONObject: ["models": models])
}

@Suite(.serialized) struct OllamaListModelsTests {

    @Test @MainActor func parsesModelsCorrectly() async throws {
        let raw: [[String: Any]] = [
            ["name": "gemma3:4b", "size": 2_000_000_000, "details": ["parameter_size": "4B"]],
            ["name": "qwen3:1.7b", "size": 1_000_000_000, "details": ["parameter_size": "1.7B"]],
        ]
        let session = makeListModelsSession { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, tagsJSON(models: raw))
        }

        let svc = OllamaService(session: session)
        let result = try await svc.listModels()

        #expect(result.count == 2)
        #expect(result[0].name == "gemma3:4b")
        #expect(result[0].size == 2_000_000_000)
        #expect(result[0].parameterSize == "4B")
        #expect(result[1].name == "qwen3:1.7b")
        #expect(result[1].parameterSize == "1.7B")
    }

    @Test @MainActor func emptyModelListReturnsEmptyArray() async throws {
        let session = makeListModelsSession { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, tagsJSON(models: []))
        }

        let svc = OllamaService(session: session)
        let result = try await svc.listModels()
        #expect(result.isEmpty)
    }

    @Test @MainActor func malformedJSONThrowsDecode() async throws {
        let session = makeListModelsSession { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data("not json at all".utf8))
        }

        let svc = OllamaService(session: session)
        await #expect(throws: OllamaError.decode("missing models field")) {
            try await svc.listModels()
        }
    }

    @Test @MainActor func networkTimeoutThrowsOllamaTimeout() async throws {
        let session = makeListModelsSession { _ in
            throw URLError(.timedOut)
        }

        let svc = OllamaService(session: session)
        await #expect(throws: OllamaError.timeout) {
            try await svc.listModels(timeout: 1)
        }
    }

    @Test @MainActor func connectionRefusedThrowsUnderlying() async throws {
        let session = makeListModelsSession { _ in
            throw URLError(.cannotConnectToHost)
        }

        let svc = OllamaService(session: session)
        var caught: OllamaError? = nil
        do {
            _ = try await svc.listModels()
        } catch let e as OllamaError {
            caught = e
        }
        // underlying wraps non-timeout URLErrors
        if case .underlying = caught { } else {
            Issue.record("Expected OllamaError.underlying, got \(String(describing: caught))")
        }
    }
}
