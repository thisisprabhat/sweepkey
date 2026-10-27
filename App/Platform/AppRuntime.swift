import SweepkeyKit
import Foundation

/// Where app data lives. DEBUG builds accept `-SweepkeySettingsPath <file>`, which moves the
/// settings, scan cache and journal next to that file so fixtures never touch real user data.
enum AppRuntime {
    static var settingsOverride: URL? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "SweepkeySettingsPath").map { URL(fileURLWithPath: $0) }
        #else
        nil
        #endif
    }

    static var settingsFile: URL { settingsOverride ?? AppPaths.settingsFile }

    static var scanCacheFile: URL {
        settingsOverride?.deletingLastPathComponent().appendingPathComponent("scan-cache.json") ?? AppPaths.scanCacheFile
    }

    static var journalFile: URL {
        settingsOverride?.deletingLastPathComponent().appendingPathComponent("journal.json") ?? AppPaths.journalFile
    }

    /// Last-run dates of the scheduled jobs, next to the journal.
    static var scheduleStateFile: URL {
        journalFile.deletingLastPathComponent().appendingPathComponent("schedule.json")
    }

    /// DEBUG only: `-SweepkeyDemo YES` runs on the mock services and fake projects under
    /// /Users/demo, for screenshots that show no real paths.
    static var demoMode: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "SweepkeyDemo")
        #else
        false
        #endif
    }

    /// DEBUG only, with `-SweepkeyDemo`: `-SweepkeyDemoPresent cleanConfirm` opens that sheet or
    /// panel once the demo data has loaded, for screenshots (see `AppModel.presentDemoScreen()`).
    static var demoPresent: String? {
        #if DEBUG
        demoMode ? UserDefaults.standard.string(forKey: "SweepkeyDemoPresent") : nil
        #else
        nil
        #endif
    }

    /// DEBUG only: `-SweepkeyStartTab caches` opens that sidebar item on launch.
    static var startTab: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "SweepkeyStartTab")
        #else
        nil
        #endif
    }

    /// DEBUG only: `-SweepkeyAutoScan YES` starts a scan on launch.
    static var autoScan: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "SweepkeyAutoScan")
        #else
        false
        #endif
    }
}
