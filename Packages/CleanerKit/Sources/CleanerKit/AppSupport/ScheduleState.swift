import Foundation

/// Last-run dates of the scheduled jobs, persisted next to the journal so a job that came due
/// while the app was not running runs once at the next launch instead of waiting a full interval.
public struct ScheduleState: Codable, Hashable, Sendable {
    /// Job id -> last run, or the moment the job was enabled (the clock starts then).
    public var lastRun: [String: Date] = [:]

    public init(lastRun: [String: Date] = [:]) {
        self.lastRun = lastRun
    }
}

public enum SchedulePlanner {
    /// What to do with one job now.
    public enum Action: Equatable, Sendable {
        /// Disabled: forget its clock, so re-enabling later starts a fresh interval.
        case forget
        /// Newly enabled: start the clock now, first run after one interval.
        case startClock
        /// Due (or overdue after a gap): run once now.
        case run
        /// Not due yet.
        case wait(TimeInterval)
    }

    public static func action(enabled: Bool, lastRun: Date?, interval: TimeInterval, now: Date) -> Action {
        guard enabled else { return .forget }
        guard let lastRun else { return .startClock }
        let elapsed = now.timeIntervalSince(lastRun)
        // A clock in the future (time zone or clock changes) counts from now.
        if elapsed < 0 { return .startClock }
        return elapsed >= interval ? .run : .wait(interval - elapsed)
    }

    /// How often the background scheduler wakes to check a job with this interval: a quarter of
    /// it, between 15 minutes and 1 hour. A job then runs at most this late after it came due.
    public static func checkInterval(for interval: TimeInterval) -> TimeInterval {
        min(max(interval / 4, 15 * 60), 3600)
    }
}

/// JSON file store for `ScheduleState`. A missing or unreadable file reads as empty.
public struct ScheduleStateStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> ScheduleState {
        guard let data = try? Data(contentsOf: fileURL) else { return ScheduleState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ScheduleState.self, from: data)) ?? ScheduleState()
    }

    public func save(_ state: ScheduleState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }
}
