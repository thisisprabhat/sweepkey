import CleanerKit
import Foundation

/// `NSBackgroundActivityScheduler` jobs for auto-scan, auto-clean and auto vault snapshot.
/// They only run while the app (or its login item) is running. Each job's last run is persisted
/// (`ScheduleState`), and the background activity only wakes the job up to check whether it is
/// due, so a job that came due while the app was closed runs once at launch, and otherwise runs
/// when its remaining interval has passed.
@MainActor
final class Scheduler {
    private let model: AppModel
    private var activities: [String: NSBackgroundActivityScheduler] = [:]
    private var intervals: [String: TimeInterval] = [:]
    private let store = ScheduleStateStore(fileURL: AppRuntime.scheduleStateFile)
    private lazy var state = store.load()
    private var running: Set<String> = []

    private enum Job: String, CaseIterable {
        case scan = "com.prabhatkumar.Cleaner.autoscan"
        case clean = "com.prabhatkumar.Cleaner.autoclean"
        case vault = "com.prabhatkumar.Cleaner.autovault"
    }

    init(model: AppModel) { self.model = model }

    private func setting(_ job: Job) -> (enabled: Bool, interval: TimeInterval) {
        let schedule = model.settings.schedule
        switch job {
        case .scan: return (schedule.autoScanEnabled, TimeInterval(schedule.autoScanIntervalHours) * 3600)
        case .clean: return (schedule.autoCleanStaleEnabled, TimeInterval(schedule.autoCleanIntervalDays) * 86400)
        case .vault: return (schedule.autoVaultSnapshotEnabled, TimeInterval(schedule.autoVaultIntervalDays) * 86400)
        }
    }

    /// Creates, updates or cancels each job to match the current settings, and runs a job that is
    /// already due (for example because it came due while the app was not running).
    func configure() {
        for job in Job.allCases {
            let (enabled, interval) = setting(job)
            sync(job, enabled: enabled, interval: interval)
            check(job)
        }
    }

    /// Applies the persisted clock to one job: forget, start, run once, or keep waiting.
    private func check(_ job: Job) {
        let (enabled, interval) = setting(job)
        let now = Date()
        switch SchedulePlanner.action(enabled: enabled, lastRun: state.lastRun[job.rawValue], interval: interval, now: now) {
        case .forget:
            if state.lastRun.removeValue(forKey: job.rawValue) != nil { persist() }
        case .startClock:
            state.lastRun[job.rawValue] = now
            persist()
        case .run:
            guard !running.contains(job.rawValue) else { return }
            Task { await runRecorded(job) }
        case .wait:
            break
        }
    }

    private func persist() {
        do { try store.save(state) } catch { AutomationLog.info("could not save schedule state: \(error.localizedDescription)") }
    }

    /// Runs the job once, recording the run first so a slow job is not started twice.
    private func runRecorded(_ job: Job) async {
        guard running.insert(job.rawValue).inserted else { return }
        defer { running.remove(job.rawValue) }
        state.lastRun[job.rawValue] = Date()
        persist()
        await run(job)
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
        let wake = SchedulePlanner.checkInterval(for: interval)
        let activity = NSBackgroundActivityScheduler(identifier: job.rawValue)
        activity.repeats = true
        activity.interval = wake
        activity.tolerance = wake / 4
        activity.qualityOfService = .utility
        activity.schedule { [weak self] completion in
            Task { @MainActor in
                self?.check(job)
                completion(.finished)
            }
        }
        activities[job.rawValue] = activity
        intervals[job.rawValue] = interval
        AutomationLog.info("scheduled \(job.rawValue) every \(Int(interval))s (checked every \(Int(wake))s)")
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
