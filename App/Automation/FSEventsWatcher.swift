import CoreServices
import Foundation

/// Watches the resolved scan roots with an FSEventStream (5 s latency). Changed paths are
/// delivered, already de-duplicated, to `onChange` on the main actor.
final class FSEventsWatcher: @unchecked Sendable {
    static let latency: CFTimeInterval = 5

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.prabhatkumar.Cleaner.fsevents")
    private let onChange: @Sendable ([String]) -> Void

    init(onChange: @escaping @Sendable ([String]) -> Void) { self.onChange = onChange }

    deinit { stop() }

    var isRunning: Bool { stream != nil }

    func start(roots: [URL]) {
        stop()
        let paths = roots.map(\.path)
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] ?? []
            watcher.onChange(Array(array.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            nil, callback, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latency, flags) else { return }
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
        AutomationLog.info("fsevents watching \(paths.count) root(s)")
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

/// Maps raw FSEvents paths to the directories worth rescanning.
enum FSEventsPlanner {
    /// Paths inside these are churn from builds and tooling, not new or changed projects.
    static func isNoise(_ path: String, artifactPaths: [String]) -> Bool {
        if path.contains("/.git/") || path.hasSuffix("/.git") || path.hasSuffix(".DS_Store") { return true }
        return artifactPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// The directory to rescan for a changed path: the containing known project, else the first
    /// directory below the scan root (a new project may have appeared there).
    static func affectedRoot(for path: String, projectPaths: [String], scanRoots: [String]) -> String? {
        if let project = projectPaths.filter({ path == $0 || path.hasPrefix($0 + "/") }).max(by: { $0.count < $1.count }) {
            return project
        }
        guard let root = scanRoots.filter({ path.hasPrefix($0 + "/") }).max(by: { $0.count < $1.count }) else { return nil }
        let rest = path.dropFirst(root.count + 1)
        guard let first = rest.split(separator: "/").first else { return nil }
        return root + "/" + first
    }
}
