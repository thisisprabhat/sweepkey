import CleanerKit
import Foundation

/// Where app data lives. DEBUG builds accept `-CleanerSettingsPath <file>`, which moves the
/// settings, scan cache and journal next to that file so fixtures never touch real user data.
enum AppRuntime {
    static var settingsOverride: URL? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "CleanerSettingsPath").map { URL(fileURLWithPath: $0) }
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

    /// DEBUG only: `-CleanerAutoScan YES` starts a scan on launch.
    static var autoScan: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "CleanerAutoScan")
        #else
        false
        #endif
    }
}
