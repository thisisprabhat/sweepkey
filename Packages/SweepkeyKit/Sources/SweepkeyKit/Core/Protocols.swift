import Foundation

public protocol ProjectScanning: Sendable {
    func scan(_ options: ScanOptions) -> AsyncThrowingStream<ScanEvent, Error>
}

public protocol CacheScanning: Sendable {
    func scanCaches() async -> [CacheGroup]
}

public protocol SafetyEvaluating: Sendable {
    func evaluate(_ candidates: [Candidate], scanRoots: [URL]) async -> [Candidate.ID: SafetyVerdict]
}

public protocol CleanExecuting: Sendable {
    func clean(
        _ candidates: [Candidate], mode: DeleteMode, dryRun: Bool,
        progress: @escaping @Sendable (CleanProgress) -> Void
    ) async -> CleanReport
    /// Restore trashed items to their original location.
    func putBack(_ items: [CleanItemResult]) async -> [CleanItemResult]
}

public protocol CleanJournaling: Sendable {
    func append(_ report: CleanReport) async throws
    /// Newest first.
    func reports() async throws -> [CleanReport]
    func lifetimeFreedBytes() async throws -> Int64
}

public protocol SecretFinding: Sendable {
    func findSecrets(_ options: VaultCollectOptions) async throws -> [SecretFile]
}

public protocol VaultExporting: Sendable {
    func export(_ request: VaultExportRequest) async throws -> VaultExportResult
}

public protocol VaultRestoring: Sendable {
    func open(_ vaultURL: URL, password: String?) async throws -> OpenedVault
    func close(_ vault: OpenedVault) async
    func planRestore(_ vault: OpenedVault, strategy: RestoreStrategy) async throws -> [RestoreAction]
    func restore(_ actions: [RestoreAction], overwrite: Bool) async throws -> RestoreResult
}
