import Foundation

actor StyleExamplesStore {
    let fileURL: URL

    init(fileURL: URL = StyleExamplesStore.defaultURL()) {
        self.fileURL = fileURL
    }

    static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/lingopulse/style_examples.jsonl")
    }

    func append(_ entry: [String: Any]) throws {
        var enriched = entry
        if enriched["timestamp"] == nil {
            enriched["timestamp"] = currentISOTimestamp()
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let data = try JSONSerialization.data(withJSONObject: enriched, options: [.sortedKeys])
        guard var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } else {
            try Data(line.utf8).write(to: fileURL, options: .atomic)
        }
    }

    func readAll() throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        var entries: [[String: Any]] = []
        for line in raw.split(separator: "\n") {
            if let data = String(line).data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                entries.append(obj)
            }
        }
        return entries
    }

    private nonisolated func currentISOTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
