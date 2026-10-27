import Foundation

/// Data the app shares with the widget through the App Group container.
struct WidgetSnapshot: Codable, Equatable {
    static let appGroup = "group.com.prabhatkumar.Cleaner"
    static let fileName = "widget-snapshot.json"

    var freeBytes: Int64
    var totalBytes: Int64
    var reclaimableBytes: Int64
    var updatedAt: Date

    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(freeBytes: 120_000_000_000, totalBytes: 500_000_000_000, reclaimableBytes: 18_000_000_000, updatedAt: Date())
    }

    static func fileURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Returns false (silently) when the App Group container is unavailable, e.g. an ad-hoc build.
    @discardableResult
    func write() -> Bool {
        guard let url = Self.fileURL() else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
