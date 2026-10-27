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

    var isRunning: Bool { stream != nil }

    func start(roots: [URL]) {
        stop()
        let paths = roots.map(\.path)
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passRetained(self).toOpaque(), retain: nil,
            release: { info in if let info { Unmanaged<FSEventsWatcher>.fromOpaque(info).release() } },
            copyDescription: nil)
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
            Self.latency, flags) else {
            Unmanaged<FSEventsWatcher>.fromOpaque(context.info!).release()
            return
        }
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
        AutomationLog.info("fsevents watching \(paths.count) root(s)")
    }

    func stop() {
        // The stream's context retains this watcher until the stream is released, so an in-flight
        // callback can never see a deallocated object. Callers must call `stop()` to let go.
        guard let stream else { return }
        self.stream = nil
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

