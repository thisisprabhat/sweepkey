import Foundation

/// Data the app shares with the widget through the App Group container.
struct WidgetSnapshot: Codable, Equatable {
    /// Info.plist key holding the resolved App Group id, `$(TeamIdentifierPrefix)com.prabhatkumar.Cleaner`.
    static let appGroupInfoKey = "CleanerAppGroup"
    static let fileName = "widget-snapshot.json"

    /// The App Group id from Info.plist, or nil when the build has no team (ad-hoc builds leave
    /// the Team ID prefix empty, and then there is no shared container to use).
    static var appGroup: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey) as? String else { return nil }
        return validatedAppGroup(value)
    }

    /// Accepts only "<10-character Team ID>.<identifier>".
    static func validatedAppGroup(_ value: String) -> String? {
        let parts = value.split(separator: ".", maxSplits: 1)
        guard parts.count == 2, parts[0].count == 10, !parts[1].isEmpty,
              parts[0].allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) })
        else { return nil }
        return value
    }

    var freeBytes: Int64
    var totalBytes: Int64
    var reclaimableBytes: Int64
    var updatedAt: Date

    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(freeBytes: 120_000_000_000, totalBytes: 500_000_000_000, reclaimableBytes: 18_000_000_000, updatedAt: Date())
    }

    static func fileURL() -> URL? {
        guard let appGroup else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
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
