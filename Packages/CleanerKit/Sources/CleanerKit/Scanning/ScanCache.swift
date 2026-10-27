import Foundation

/// Persists the last scan result as JSON.
public actor ScanCache {
    public struct Snapshot: Codable, Sendable {
        public var savedAt: Date
        public var projects: [Project]
    }

    private let url: URL

    public init(url: URL = AppPaths.scanCacheFile) {
        self.url = url
    }

    public func save(_ projects: [Project], at date: Date = Date()) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Snapshot(savedAt: date, projects: projects))
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// nil when no cache exists or it cannot be decoded.
    public func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }
}
