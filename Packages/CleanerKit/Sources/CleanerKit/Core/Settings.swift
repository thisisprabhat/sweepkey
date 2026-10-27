import Foundation

// Decoding tolerates missing keys (decodeIfPresent ?? default) and ignores unknown keys.

public struct VaultSettings: Codable, Hashable, Sendable {
    public var destination: URL? = nil
    public var defaultFormat: VaultExportFormat = .folder
    public var alwaysCollect: [String] = ["pubspec.yaml"]
    public var extraPatterns: [String] = []
    public var includeUncommittedWork = false
    public var scanContents = false
    public var keepVersions = 5

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case destination, defaultFormat, alwaysCollect, extraPatterns
        case includeUncommittedWork, scanContents, keepVersions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        destination = try c.decodeIfPresent(URL.self, forKey: .destination)
        defaultFormat = try c.decodeIfPresent(VaultExportFormat.self, forKey: .defaultFormat) ?? .folder
        alwaysCollect = try c.decodeIfPresent([String].self, forKey: .alwaysCollect) ?? ["pubspec.yaml"]
        extraPatterns = try c.decodeIfPresent([String].self, forKey: .extraPatterns) ?? []
        includeUncommittedWork = try c.decodeIfPresent(Bool.self, forKey: .includeUncommittedWork) ?? false
        scanContents = try c.decodeIfPresent(Bool.self, forKey: .scanContents) ?? false
        keepVersions = try c.decodeIfPresent(Int.self, forKey: .keepVersions) ?? 5
    }
}

public struct ScheduleSettings: Codable, Hashable, Sendable {
    public var autoScanEnabled = false
    public var autoScanIntervalHours = 24
    public var autoCleanStaleEnabled = false
    public var autoCleanIntervalDays = 7
    public var autoVaultSnapshotEnabled = false
    public var autoVaultIntervalDays = 7

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case autoScanEnabled, autoScanIntervalHours, autoCleanStaleEnabled
        case autoCleanIntervalDays, autoVaultSnapshotEnabled, autoVaultIntervalDays
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoScanEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoScanEnabled) ?? false
        autoScanIntervalHours = try c.decodeIfPresent(Int.self, forKey: .autoScanIntervalHours) ?? 24
        autoCleanStaleEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoCleanStaleEnabled) ?? false
        autoCleanIntervalDays = try c.decodeIfPresent(Int.self, forKey: .autoCleanIntervalDays) ?? 7
        autoVaultSnapshotEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoVaultSnapshotEnabled) ?? false
        autoVaultIntervalDays = try c.decodeIfPresent(Int.self, forKey: .autoVaultIntervalDays) ?? 7
    }
}

public struct CleanerSettings: Codable, Hashable, Sendable {
    public var scanRoots: [URL] = []
    public var excludedPaths: [URL] = []
    public var pinnedProjects: [URL] = []
    public var ruleOverrides: [String: Bool] = [:]
    public var customRules: [Rule] = []
    public var staleAfterDays = 30
    public var defaultDeleteMode: DeleteMode = .permanent
    public var requireVaultBeforeClean = false
    public var vault = VaultSettings()
    public var lowSpaceAlertsEnabled = true
    public var lowSpaceThresholdGB = 20
    public var schedule = ScheduleSettings()
    public var showMenuBarExtra = true
    public var launchAtLogin = false
    public var hasCompletedOnboarding = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case scanRoots, excludedPaths, pinnedProjects, ruleOverrides, customRules
        case staleAfterDays, defaultDeleteMode, requireVaultBeforeClean, vault
        case lowSpaceAlertsEnabled, lowSpaceThresholdGB, schedule
        case showMenuBarExtra, launchAtLogin, hasCompletedOnboarding
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scanRoots = try c.decodeIfPresent([URL].self, forKey: .scanRoots) ?? []
        excludedPaths = try c.decodeIfPresent([URL].self, forKey: .excludedPaths) ?? []
        pinnedProjects = try c.decodeIfPresent([URL].self, forKey: .pinnedProjects) ?? []
        ruleOverrides = try c.decodeIfPresent([String: Bool].self, forKey: .ruleOverrides) ?? [:]
        customRules = try c.decodeIfPresent([Rule].self, forKey: .customRules) ?? []
        staleAfterDays = try c.decodeIfPresent(Int.self, forKey: .staleAfterDays) ?? 30
        defaultDeleteMode = try c.decodeIfPresent(DeleteMode.self, forKey: .defaultDeleteMode) ?? .permanent
        requireVaultBeforeClean = try c.decodeIfPresent(Bool.self, forKey: .requireVaultBeforeClean) ?? false
        vault = try c.decodeIfPresent(VaultSettings.self, forKey: .vault) ?? VaultSettings()
        lowSpaceAlertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .lowSpaceAlertsEnabled) ?? true
        lowSpaceThresholdGB = try c.decodeIfPresent(Int.self, forKey: .lowSpaceThresholdGB) ?? 20
        schedule = try c.decodeIfPresent(ScheduleSettings.self, forKey: .schedule) ?? ScheduleSettings()
        showMenuBarExtra = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarExtra) ?? true
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
    }
}

public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = AppPaths.settingsFile) {
        self.fileURL = fileURL
    }

    /// Defaults if the file is missing or corrupt.
    public func load() -> CleanerSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(CleanerSettings.self, from: data)
        else { return CleanerSettings() }
        return settings
    }

    /// Atomic write, pretty JSON, sorted keys.
    public func save(_ settings: CleanerSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

public enum AppPaths {
    /// ~/Library/Application Support/Cleaner (created on access)
    public static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Cleaner", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    public static var settingsFile: URL { applicationSupport.appendingPathComponent("settings.json") }
    public static var journalFile: URL { applicationSupport.appendingPathComponent("journal.json") }
    public static var scanCacheFile: URL { applicationSupport.appendingPathComponent("scan-cache.json") }
    /// ~/Documents/Cleaner Vault
    public static var defaultVaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Cleaner Vault", isDirectory: true)
    }
}
