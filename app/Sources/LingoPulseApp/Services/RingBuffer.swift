import Foundation
import Darwin

actor RingBuffer {
    private let fileURL: URL
    private let size: Int

    init(fileURL: URL = RingBuffer.defaultURL(), size: Int = 5) {
        self.fileURL = fileURL
        self.size = size
    }

    static func defaultURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".cache/lingopulse/undo_ring.json")
    }

    func append(_ entry: [String: Any]) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        let handle = try FileHandle(forUpdating: fileURL)
        defer {
            flock(handle.fileDescriptor, LOCK_UN)
            handle.closeFile()
        }
        flock(handle.fileDescriptor, LOCK_EX)

        var entries = readEntries(handle: handle)
        entries.append(entry)
        if entries.count > size {
            entries = Array(entries.suffix(size))
        }
        try writeEntries(entries, handle: handle)
    }

    func popLatest() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let handle = try FileHandle(forUpdating: fileURL)
        defer {
            flock(handle.fileDescriptor, LOCK_UN)
            handle.closeFile()
        }
        flock(handle.fileDescriptor, LOCK_EX)

        var entries = readEntries(handle: handle)
        guard !entries.isEmpty else { return nil }
        let last = entries.removeLast()
        try writeEntries(entries, handle: handle)
        return last
    }

    func listAll() throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            flock(handle.fileDescriptor, LOCK_UN)
            handle.closeFile()
        }
        flock(handle.fileDescriptor, LOCK_SH)

        return readEntries(handle: handle).reversed()
    }

    func findMatching(_ predicate: ([String: Any]) -> Bool) throws -> [String: Any]? {
        try listAll().first(where: predicate)
    }

    private func readEntries(handle: FileHandle) -> [[String: Any]] {
        handle.seek(toFileOffset: 0)
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = obj["entries"] as? [[String: Any]]
        else { return [] }
        return entries
    }

    private func writeEntries(_ entries: [[String: Any]], handle: FileHandle) throws {
        let data = try JSONSerialization.data(withJSONObject: ["entries": entries], options: [])
        handle.seek(toFileOffset: 0)
        handle.truncateFile(atOffset: 0)
        handle.write(data)
    }
}
