import CleanerKit
import Foundation

/// `NSBackgroundActivityScheduler` jobs for auto-scan, auto-clean and auto vault snapshot.
/// They only run while the app (or its login item) is running.
@MainActor
final class Scheduler {
    private let model: AppModel
    private var activities: [String: NSBackgroundActivityScheduler] = [:]
    private var intervals: [String: TimeInterval] = [:]

    private enum Job: String {
        case scan = "com.prabhatkumar.Cleaner.autoscan"
        case clean = "com.prabhatkumar.Cleaner.autoclean"
        case vault = "com.prabhatkumar.Cleaner.autovault"
    }

    init(model: AppModel) { self.model = model }

    /// Creates, updates or cancels each job to match the current settings.
    func configure() {
        let schedule = model.settings.schedule
        sync(.scan, enabled: schedule.autoScanEnabled, interval: TimeInterval(schedule.autoScanIntervalHours) * 3600)
        sync(.clean, enabled: schedule.autoCleanStaleEnabled, interval: TimeInterval(schedule.autoCleanIntervalDays) * 86400)
        sync(.vault, enabled: schedule.autoVaultSnapshotEnabled, interval: TimeInterval(schedule.autoVaultIntervalDays) * 86400)
    }

    private func sync(_ job: Job, enabled: Bool, interval: TimeInterval) {
        guard enabled else {
            if let activity = activities.removeValue(forKey: job.rawValue) {
                activity.invalidate()
                intervals[job.rawValue] = nil
            }
            return
        }
        if activities[job.rawValue] != nil, intervals[job.rawValue] == interval { return }
        activities[job.rawValue]?.invalidate()
        let activity = NSBackgroundActivityScheduler(identifier: job.rawValue)
        activity.repeats = true
        activity.interval = interval
        activity.tolerance = max(60, interval / 10)
        activity.qualityOfService = .utility
        activity.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.run(job)
                completion(.finished)
            }
        }
        activities[job.rawValue] = activity
        intervals[job.rawValue] = interval
        AutomationLog.info("scheduled \(job.rawValue) every \(Int(interval))s")
    }

    private func run(_ job: Job) async {
        AutomationLog.info("running job \(job.rawValue)")
        switch job {
        case .scan:
            guard !model.settings.scanRoots.isEmpty else { return }
            if model.scanState.isScanning { await model.waitForScan() } else {
                model.scanGeneration += 1
                await model.runScan(generation: model.scanGeneration)
            }
            AutomationState.shared.resultsMayBeOutdated = false
            let size = ByteCountFormatter.string(fromByteCount: model.reclaimableBytes, countStyle: .file)
            await Notifier.shared.post(
                title: "Scan finished",
                body: "\(model.projects.count) project(s), \(size) reclaimable.")
        case .clean:
            guard !model.settings.scanRoots.isEmpty else { return }
            // Fresh results first: the cache may be old. Safe rules and stale projects only.
            if model.scanState.isScanning { await model.waitForScan() } else {
                model.scanGeneration += 1
                await model.runScan(generation: model.scanGeneration)
            }
            let outcome = await model.cleanSafeItems(dryRun: false)
            await Notifier.shared.post(title: "Auto-clean finished", body: outcome.summary)
        case .vault:
            do {
                if let result = try await model.snapshotVault() {
                    await Notifier.shared.post(
                        title: "Vault snapshot saved",
                        body: "\(result.copiedCount) copied, \(result.unchangedCount) unchanged.")
                } else {
                    await Notifier.shared.post(title: "Vault snapshot skipped", body: "No secret files were found.")
                }
            } catch {
                await Notifier.shared.post(title: "Vault snapshot failed", body: error.localizedDescription)
            }
        }
    }
}
