import AppKit
import CleanerKit
import Foundation

/// Checks free space every 15 minutes and on wake; alerts at most once every 6 hours.
@MainActor
final class LowSpaceMonitor {
    private let model: AppModel
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private static let lastAlertKey = "CleanerLastLowSpaceAlert"

    init(model: AppModel) { self.model = model }

    /// DEBUG only: `-CleanerLowSpaceThresholdGB <n>` overrides the stored threshold.
    private var thresholdGB: Int {
        #if DEBUG
        if UserDefaults.standard.object(forKey: "CleanerLowSpaceThresholdGB") != nil {
            return UserDefaults.standard.integer(forKey: "CleanerLowSpaceThresholdGB")
        }
        #endif
        return model.settings.lowSpaceThresholdGB
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
        Task { await check() }
    }

    func check(now: Date = Date()) async {
        guard let disk = DiskInfo.current() else { return }
        let lastAlert = UserDefaults.standard.object(forKey: Self.lastAlertKey) as? Date
        let due = LowSpacePolicy.shouldAlert(
            freeBytes: disk.freeBytes, thresholdGB: thresholdGB, lastAlert: lastAlert, now: now,
            enabled: model.settings.lowSpaceAlertsEnabled)
        AutomationLog.info(
            "low-space check: free=\(disk.freeBytes) threshold=\(thresholdGB)GB alert=\(due)")
        guard due else { return }
        let free = ByteCountFormatter.string(fromByteCount: disk.freeBytes, countStyle: .file)
        let posted = await Notifier.shared.post(
            title: "Disk space is low",
            body: "Only \(free) free. Clean safe items to reclaim space.",
            category: Notifier.lowSpaceCategory)
        // Only a delivered alert starts the 6 h quiet period.
        if posted { UserDefaults.standard.set(now, forKey: Self.lastAlertKey) }
    }
}
