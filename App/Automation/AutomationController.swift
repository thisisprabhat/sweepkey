import AppKit
import SweepkeyKit
import Foundation
import Observation

/// Owns every background automation piece and starts it at launch (independent of any window).
@MainActor
final class AutomationController {
    static let shared = AutomationController()

    private let model = AppModel.shared
    private lazy var lowSpace = LowSpaceMonitor(model: model)
    private lazy var scheduler = Scheduler(model: model)
    private let servicesProvider = ServicesProvider()
    private var watcher: FSEventsWatcher?
    private var started = false

    private var pendingRoots: Set<String> = []
    private var rescanTask: Task<Void, Never>?
    private var isRescanning = false
    private var lastRescan = Date.distantPast
    private static let rescanCooldown: TimeInterval = 60

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        let launchedAtLogin = Self.wasLaunchedAtLogin()
        AutomationState.shared.launchedAtLogin = launchedAtLogin
        if launchedAtLogin && model.settings.showMenuBarExtra { enterAccessoryMode() }
        observeWindows()

        Notifier.shared.configure()
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()

        reconcileLoginItem()
        Task {
            await model.loadJournal()
            await model.loadCachedScan()
            WidgetSnapshotWriter.update(model: model)
        }
        lowSpace.start()
        scheduler.configure()
        restartWatcher()

        track({ self.model.settings }, { [self] in
            scheduler.configure()
            restartWatcher()
        })
        track({ (self.model.reclaimableBytes, self.model.diskRefreshToken, self.model.scanState.isScanning) }, { [self] in
            WidgetSnapshotWriter.update(model: model)
        })
        AutomationLog.info("automation started (menu bar extra \(model.settings.showMenuBarExtra ? "enabled" : "disabled"), login launch \(launchedAtLogin))")
    }

    // MARK: Login item and accessory mode

    private static func wasLaunchedAtLogin() -> Bool {
        let keyAELaunchedAsLogInItem: AEKeyword = 0x6c676974 // 'lgit'
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    private func reconcileLoginItem() {
        // Never register here: only an explicit settings change does. If the user turned the item
        // off in System Settings, reflect that; leave a pending approval alone.
        if LoginItem.needsApproval { return }
        let actual = LoginItem.isEnabled
        if model.settings.launchAtLogin != actual {
            AutomationLog.info("login item state is \(actual); updating the setting to match")
            model.settings.launchAtLogin = actual
        }
    }

    private func enterAccessoryMode() {
        NSApp.setActivationPolicy(.accessory)
        // SwiftUI opens the main window at launch; keep a login launch menu-bar-only.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            for window in NSApp.windows where window.styleMask.contains(.titled) && window.canBecomeMain {
                window.close()
            }
        }
        AutomationLog.info("running as accessory app (login launch)")
    }

    private func observeWindows() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main
        ) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let window, window.styleMask.contains(.titled),
                      NSApp.activationPolicy() == .accessory else { return }
                NSApp.setActivationPolicy(.regular)
            }
        }
    }

    // MARK: Observation

    private func track<T>(_ read: @escaping @MainActor () -> T, _ onChange: @escaping @MainActor () -> Void) {
        withObservationTracking {
            _ = read()
        } onChange: { [weak self] in
            Task { @MainActor in
                onChange()
                self?.track(read, onChange)
            }
        }
    }

    // MARK: FSEvents

    private func restartWatcher() {
        let roots = AppLogic.resolve(model.settings.scanRoots).filter { FileManager.default.fileExists(atPath: $0.path) }
        guard roots.map(\.path) != watchedRoots else { return }
        watchedRoots = roots.map(\.path)
        watcher?.stop()
        guard !roots.isEmpty else { watcher = nil; return }
        let fresh = FSEventsWatcher { [weak self] paths in
            Task { @MainActor in self?.noteChanges(paths) }
        }
        fresh.start(roots: roots)
        watcher = fresh
    }

    private var watchedRoots: [String] = []

    private func noteChanges(_ paths: [String]) {
        let artifacts = model.allCandidates.map(\.url.path)
        let projectPaths = model.projects.map(\.url.path)
        let affected = Set(paths.compactMap { path -> String? in
            guard !FSEventsPlanner.isNoise(path, artifactPaths: artifacts) else { return nil }
            return FSEventsPlanner.affectedRoot(for: path, projectPaths: projectPaths, scanRoots: watchedRoots)
        })
        guard !affected.isEmpty else { return }
        AutomationState.shared.resultsMayBeOutdated = true
        guard model.settings.schedule.autoScanEnabled else { return }
        pendingRoots.formUnion(affected)
        scheduleRescan()
    }

    /// Debounces rescans. Only the waiting sleep is ever cancelled; a rescan in flight finishes,
    /// and changes arriving meanwhile are queued for the next pass.
    private func scheduleRescan() {
        guard !isRescanning else { return }
        rescanTask?.cancel()
        let wait = max(FSEventsWatcher.latency, Self.rescanCooldown - Date().timeIntervalSince(lastRescan))
        rescanTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            await performRescan()
        }
    }

    private func performRescan() async {
        isRescanning = true
        let roots = pendingRoots
        pendingRoots = []
        lastRescan = Date()
        AutomationLog.info("fsevents rescan of \(roots.count) root(s)")
        let merged = await model.rescanMerging(roots.map { URL(fileURLWithPath: $0) })
        if !merged {
            // A full scan was running, or the scan failed: keep the roots and the stale flag.
            pendingRoots.formUnion(roots)
            AutomationState.shared.resultsMayBeOutdated = true
        } else if pendingRoots.isEmpty {
            AutomationState.shared.resultsMayBeOutdated = false
        }
        isRescanning = false
        if !pendingRoots.isEmpty { scheduleRescan() }
    }
}
