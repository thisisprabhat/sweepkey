import Foundation

public actor JSONJournal: CleanJournaling {
    private let fileURL: URL
    private static let cap = 500

    public init(fileURL: URL = AppPaths.journalFile) {
        self.fileURL = fileURL
    }

    private func load() throws -> [CleanReport] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([CleanReport].self, from: data)
    }

    public func append(_ report: CleanReport) throws {
        var all = try load()
        all.insert(report, at: 0)
        if all.count > Self.cap { all.removeLast(all.count - Self.cap) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(all)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    public func reports() throws -> [CleanReport] { try load() }

    public func lifetimeFreedBytes() throws -> Int64 {
        try load().reduce(0) { $0 + ($1.dryRun ? 0 : $1.freedBytes) }
    }
}
