import Foundation
import Darwin

actor HistoryStore {
    private let fileURL: URL

    init(fileURL: URL = HistoryStore.defaultURL()) {
        self.fileURL = fileURL
    }

    static func defaultURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/lingopulse/history.jsonl")
    }

    func append(_ entry: [String: Any]) throws {
        var entry = entry
        if entry["timestamp"] == nil {
            entry["timestamp"] = Self.currentTimestamp()
        }

        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        var line = String(decoding: data, as: UTF8.self)
        line.append("\n")

        if let handle = FileHandle(forWritingAtPath: fileURL.path) {
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        } else {
            try Data(line.utf8).write(to: fileURL, options: .atomic)
        }
    }

    func readAll() throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        return raw
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { line -> [String: Any]? in
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }
                return obj
            }
    }

    private static func currentTimestamp() -> String {
        var formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
