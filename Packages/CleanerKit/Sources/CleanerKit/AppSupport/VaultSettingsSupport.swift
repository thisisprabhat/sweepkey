import Foundation

public extension CleanerSettings {
    /// Vault collect options from the settings, with resolved paths. The roots default to the scan
    /// roots (settings order, which decides vault folder names for same-named roots).
    func vaultCollectOptions(roots: [URL]? = nil) -> VaultCollectOptions {
        VaultCollectOptions(
            roots: AppLogic.resolve(roots ?? scanRoots), excludedPaths: AppLogic.resolve(excludedPaths),
            extraPatterns: vault.extraPatterns, alwaysCollect: vault.alwaysCollect,
            includeUncommittedWork: vault.includeUncommittedWork, scanContents: vault.scanContents)
    }

    /// The folder vault destination: the configured one, else `~/Documents/Cleaner Vault`. Resolved.
    var vaultFolderDestination: URL {
        (vault.destination ?? AppPaths.defaultVaultDirectory).standardizedFileURL.resolvingSymlinksInPath()
    }
}

/// Per-session changes the Vault screen makes on top of the settings. A nil field follows the
/// settings, so later settings changes still show through.
public struct VaultCollectOverrides: Hashable, Sendable {
    public var roots: [URL]?
    public var includeUncommittedWork: Bool?
    public var scanContents: Bool?
    public var alwaysCollect: [String]?

    public init(
        roots: [URL]? = nil, includeUncommittedWork: Bool? = nil, scanContents: Bool? = nil,
        alwaysCollect: [String]? = nil
    ) {
        self.roots = roots
        self.includeUncommittedWork = includeUncommittedWork
        self.scanContents = scanContents
        self.alwaysCollect = alwaysCollect
    }

    public var isEmpty: Bool { self == VaultCollectOverrides() }

    /// The settings' options with these overrides applied (roots resolved).
    public func applied(to settings: CleanerSettings) -> VaultCollectOptions {
        var options = settings.vaultCollectOptions(roots: roots)
        if let includeUncommittedWork { options.includeUncommittedWork = includeUncommittedWork }
        if let scanContents { options.scanContents = scanContents }
        if let alwaysCollect { options.alwaysCollect = alwaysCollect }
        return options
    }
}

/// The "require a vault export before cleaning" step, shared by the app and the CLI: collect the
/// secrets of the projects being cleaned with the settings' options, lay them out like a full
/// collection, and export them (folder format) to the settings' vault destination.
public enum VaultBeforeClean {
    public struct Outcome: Sendable {
        /// nil when there was nothing to export (no project artifacts, or no secrets found).
        public var result: VaultExportResult?
        public var files: [SecretFile]
        public var warnings: [String]
    }

    /// Whether a run must export the vault first: the setting is on, it is a real run, and the
    /// user did not pass the explicit bypass (`cleaner clean --skip-vault`).
    public static func isRequired(settings: CleanerSettings, dryRun: Bool, skip: Bool) -> Bool {
        settings.requireVaultBeforeClean && !dryRun && !skip
    }

    /// Distinct, resolved project roots of the candidates (global caches have none).
    public static func affectedProjects(_ candidates: [Candidate]) -> [URL] {
        AppLogic.resolve(candidates.filter { $0.kind == .projectArtifact }.compactMap(\.projectRoot))
    }

    /// Throws when collection or export fails; the caller must then not clean.
    public static func run(
        candidates: [Candidate], settings: CleanerSettings, layoutRoots: [URL] = [],
        destination: URL? = nil,
        collect: @Sendable (VaultCollectOptions) async throws -> (files: [SecretFile], warnings: [String]),
        exporter: any VaultExporting
    ) async throws -> Outcome {
        let projects = affectedProjects(candidates)
        guard !projects.isEmpty else { return Outcome(result: nil, files: [], warnings: []) }
        let found = try await collect(settings.vaultCollectOptions(roots: projects))
        let roots = AppLogic.resolve(settings.scanRoots + layoutRoots)
        let files = VaultLayout.rebase(found.files, scanRoots: roots + projects.map { $0.deletingLastPathComponent() })
        guard !files.isEmpty else { return Outcome(result: nil, files: [], warnings: found.warnings) }
        let result = try await exporter.export(VaultExportRequest(
            files: files, destination: destination ?? settings.vaultFolderDestination, format: .folder,
            keepVersions: settings.vault.keepVersions))
        return Outcome(result: result, files: files, warnings: found.warnings)
    }
}
