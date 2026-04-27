import Testing
import Foundation
@testable import LingoPulseApp

// MARK: - Helpers

private func makeTempConfigDir() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("sbs-\(UUID().uuidString)")
}

private func waitForPort(_ server: ShellBridgeServer, timeout: TimeInterval = 3.0) async throws -> UInt16 {
    let deadline = Date().addingTimeInterval(timeout)
    while server.port == nil {
        if Date() > deadline { throw TestError.timeout }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    return server.port!
}

private func post(
    path: String = "/refine",
    method: String = "POST",
    port: UInt16,
    token: String?,
    body: Data?
) async throws -> (Int, Data) {
    var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
    req.httpMethod = method
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token {
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    req.httpBody = body
    let (data, response) = try await URLSession.shared.data(for: req)
    let status = (response as! HTTPURLResponse).statusCode
    return (status, data)
}

private func jsonBody(_ dict: [String: String]) -> Data {
    try! JSONSerialization.data(withJSONObject: dict)
}

private enum TestError: Error { case timeout }

// MARK: - Tests

@Suite(.serialized) struct ShellBridgeServerTests {

    // MARK: 1. Startup: token file 0600, port file created

    @Test func startupCreatesTokenAndPortFiles() async throws {
        let dir = makeTempConfigDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let server = ShellBridgeServer(refine: { $0 }, configDir: dir)
        try server.start()
        defer { server.stop() }

        _ = try await waitForPort(server)

        let tokenFile = dir.appendingPathComponent("shell-token")
        let portFile  = dir.appendingPathComponent("shell-port")

        #expect(FileManager.default.fileExists(atPath: tokenFile.path))
        #expect(FileManager.default.fileExists(atPath: portFile.path))

        let attrs = try FileManager.default.attributesOfItem(atPath: tokenFile.path)
        let perms = attrs[.posixPermissions] as? Int
        #expect(perms == 0o600)

        let portStr = try String(contentsOf: portFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(UInt16(portStr) == server.port)
    }

    // MARK: 2. Valid POST /refine returns refined text

    @Test func validRequestReturnsRefinedText() async throws {
        let dir = makeTempConfigDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let server = ShellBridgeServer(refine: { text in "REFINED: \(text)" }, configDir: dir)
        try server.start()
        defer { server.stop() }

        let port  = try await waitForPort(server)
        let token = try #require(server.token)

        let (status, data) = try await post(port: port, token: token, body: jsonBody(["text": "hello"]))
        #expect(status == 200)

        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["refined"] as? String == "REFINED: hello")
    }

    // MARK: 3. Wrong token → 401

    @Test func wrongTokenReturns401() async throws {
        let dir = makeTempConfigDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let server = ShellBridgeServer(refine: { $0 }, configDir: dir)
        try server.start()
        defer { server.stop() }

        let port = try await waitForPort(server)

        let (status, _) = try await post(port: port, token: "wrong-token", body: jsonBody(["text": "hi"]))
        #expect(status == 401)
    }

    // MARK: 4. No Authorization header → 401

    @Test func noAuthHeaderReturns401() async throws {
        let dir = makeTempConfigDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let server = ShellBridgeServer(refine: { $0 }, configDir: dir)
        try server.start()
        defer { server.stop() }

        let port = try await waitForPort(server)

        let (status, _) = try await post(port: port, token: nil, body: jsonBody(["text": "hi"]))
        #expect(status == 401)
    }

    // MARK: 5. GET /refine → 405

    @Test func getReturns405() async throws {
        let dir = makeTempConfigDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let server = ShellBridgeServer(refine: { $0 }, configDir: dir)
        try server.start()
        defer { server.stop() }

        let port  = try await waitForPort(server)
        let token = try #require(server.token)

        let (status, _) = try await post(method: "GET", port: port, token: token, body: nil)
        #expect(status == 405)
    }

    // MARK: 6. Malformed JSON → 400

    @Test func malformedJsonReturns400() async throws {
        let dir = makeTempConfigDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let server = ShellBridgeServer(refine: { $0 }, configDir: dir)
        try server.start()
        defer { server.stop() }

        let port  = try await waitForPort(server)
        let token = try #require(server.token)

        let (status, _) = try await post(port: port, token: token, body: Data("not json{{{".utf8))
        #expect(status == 400)
    }

    // MARK: 7. Body > 256 KB → 413

    @Test func largeBodyReturns413() async throws {
        let dir = makeTempConfigDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let server = ShellBridgeServer(refine: { $0 }, configDir: dir)
        try server.start()
        defer { server.stop() }

        let port  = try await waitForPort(server)
        let token = try #require(server.token)

        // Build a body just over 256 KB
        let bigText = String(repeating: "x", count: 256 * 1024 + 1)
        let bigBody = try! JSONSerialization.data(withJSONObject: ["text": bigText])

        let (status, _) = try await post(port: port, token: token, body: bigBody)
        #expect(status == 413)
    }

    // MARK: 8. stop() releases port; second start() succeeds

    @Test func stopReleasesPortAndSecondStartSucceeds() async throws {
        let dir = makeTempConfigDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let server = ShellBridgeServer(refine: { $0 }, configDir: dir)
        try server.start()
        let firstPort = try await waitForPort(server)
        server.stop()

        // Brief pause to let the OS reclaim the port binding
        try await Task.sleep(nanoseconds: 200_000_000)

        try server.start()
        let secondPort = try await waitForPort(server)
        server.stop()

        // Both starts succeeded (ports may differ since ephemeral)
        #expect(firstPort > 0)
        #expect(secondPort > 0)
    }
}
