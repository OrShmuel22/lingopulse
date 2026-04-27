import Foundation
import Network

final class ShellBridgeServer {
    private let refine: (String) async throws -> String
    private let configDir: URL

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.lingopulse.shellbridge", attributes: .concurrent)

    private(set) var port: UInt16?
    private(set) var token: String?

    init(
        refine: @escaping (String) async throws -> String,
        configDir: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/lingopulse")
    ) {
        self.refine = refine
        self.configDir = configDir
    }

    func start() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: configDir, withIntermediateDirectories: true)

        let tok = try loadOrCreateToken()
        self.token = tok

        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: "127.0.0.1",
            port: NWEndpoint.Port.any
        )

        let listener = try NWListener(using: params)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.listener?.port?.rawValue {
                    self?.port = port
                    self?.persistPort(port)
                    Log.info("ShellBridgeServer: listening on 127.0.0.1:\(port)")
                }
            case .failed(let error):
                Log.error("ShellBridgeServer: listener failed: \(error)")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        Log.info("ShellBridgeServer: stopped")
    }

    // MARK: - Token

    private func loadOrCreateToken() throws -> String {
        let tokenFile = configDir.appendingPathComponent("shell-token")
        let path = tokenFile.path

        if FileManager.default.fileExists(atPath: path) {
            let existing = try String(contentsOf: tokenFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !existing.isEmpty { return existing }
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else {
            throw ShellBridgeError.tokenGeneration
        }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        try hex.write(to: tokenFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path
        )
        return hex
    }

    // MARK: - Port persistence

    private func persistPort(_ port: UInt16) {
        let portFile = configDir.appendingPathComponent("shell-port")
        try? "\(port)".write(to: portFile, atomically: true, encoding: .utf8)
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(connection: connection, accumulated: Data())
    }

    private func receiveHTTPRequest(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                Log.error("ShellBridgeServer: receive error: \(error)")
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let data { buffer.append(data) }

            // Look for end of headers
            let headerDelimiter = Data("\r\n\r\n".utf8)
            guard let headerEnd = buffer.range(of: headerDelimiter) else {
                if isComplete {
                    self.sendResponse(connection: connection, status: 400, body: #"{"error":"incomplete request"}"#)
                } else {
                    self.receiveHTTPRequest(connection: connection, accumulated: buffer)
                }
                return
            }

            let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
            let bodyStart = headerEnd.upperBound
            guard let headerText = String(data: headerData, encoding: .utf8) else {
                self.sendResponse(connection: connection, status: 400, body: #"{"error":"invalid headers"}"#)
                return
            }

            let lines = headerText.components(separatedBy: "\r\n")
            guard let requestLine = lines.first else {
                self.sendResponse(connection: connection, status: 400, body: #"{"error":"missing request line"}"#)
                return
            }

            let parts = requestLine.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2 else {
                self.sendResponse(connection: connection, status: 400, body: #"{"error":"malformed request line"}"#)
                return
            }

            let method = String(parts[0])
            let path = String(parts[1])

            guard path == "/refine" else {
                self.sendResponse(connection: connection, status: 404, body: #"{"error":"not found"}"#)
                return
            }

            guard method == "POST" else {
                self.sendResponse(connection: connection, status: 405, body: #"{"error":"method not allowed"}"#)
                return
            }

            // Parse headers into a dictionary
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colonIdx = line.firstIndex(of: ":") else { continue }
                let key = String(line[line.startIndex..<colonIdx]).lowercased().trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }

            // Auth check
            let expectedAuth = "Bearer \(self.token ?? "")"
            guard headers["authorization"] == expectedAuth else {
                self.sendResponse(connection: connection, status: 401, body: #"{"error":"unauthorized"}"#)
                return
            }

            let contentLength = headers["content-length"].flatMap { Int($0) } ?? 0
            let maxBodySize = 256 * 1024

            guard contentLength <= maxBodySize else {
                self.sendResponse(connection: connection, status: 413, body: #"{"error":"request body too large"}"#)
                return
            }

            let alreadyReceived = buffer.count - bodyStart
            if alreadyReceived >= contentLength {
                let bodyData = Data(buffer[bodyStart..<(bodyStart + contentLength)])
                self.processBody(bodyData, connection: connection)
            } else {
                let remaining = contentLength - alreadyReceived
                self.receiveBody(
                    connection: connection,
                    accumulated: Data(buffer[bodyStart...]),
                    needed: remaining,
                    total: contentLength
                )
            }
        }
    }

    private func receiveBody(
        connection: NWConnection,
        accumulated: Data,
        needed: Int,
        total: Int
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: needed) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                Log.error("ShellBridgeServer: body receive error: \(error)")
                connection.cancel()
                return
            }
            var buf = accumulated
            if let data { buf.append(data) }
            if buf.count >= total {
                self.processBody(Data(buf.prefix(total)), connection: connection)
            } else {
                self.receiveBody(
                    connection: connection,
                    accumulated: buf,
                    needed: total - buf.count,
                    total: total
                )
            }
        }
    }

    private func processBody(_ body: Data, connection: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let text = json["text"] as? String else {
            sendResponse(connection: connection, status: 400, body: #"{"error":"invalid JSON or missing 'text' field"}"#)
            return
        }

        Task {
            do {
                let refined = try await self.refine(text)
                let responseBody = encodeJSON(["refined": refined]) ?? #"{"refined":""}"#
                self.sendResponse(connection: connection, status: 200, body: responseBody)
            } catch {
                Log.error("ShellBridgeServer: refine error: \(error)")
                let msg = error.localizedDescription
                let responseBody = encodeJSON(["error": msg]) ?? #"{"error":"internal error"}"#
                self.sendResponse(connection: connection, status: 500, body: responseBody)
            }
        }
    }

    // MARK: - Response

    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let bodyData = Data(body.utf8)
        let statusText = httpStatusText(status)
        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func httpStatusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Content Too Large"
        case 500: return "Internal Server Error"
        default:  return "Unknown"
        }
    }

    private func encodeJSON(_ dict: [String: String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Errors

enum ShellBridgeError: Error {
    case tokenGeneration
}
