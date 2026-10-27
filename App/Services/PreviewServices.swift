import SweepkeyKit
import Foundation

// In-app mock implementations of the Core protocols. They return realistic fake data
// after small delays. Task 7 swaps these for the live services.

extension AppServices {
    static let preview = AppServices(
        scanner: MockScanner(), caches: MockCacheScanner(), safety: MockSafety(),
        cleaner: MockCleaner(), journal: MockJournal(), secrets: MockSecretFinder(),
        vaultExporter: MockVaultExporter(), vaultRestorer: MockVaultRestorer(),
        settingsStore: SettingsStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("sweepkey-preview-settings.json")),
        ruleCatalog: MockRuleCatalog())
}

struct MockRuleCatalog: RuleCatalog {
    func rules() -> [Rule] { MockData.rules }
}

struct MockScanner: ProjectScanning {
    func scan(_ options: ScanOptions) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let started = Date()
                var found = 0
                var bytes: Int64 = 0
                var visited = 0
                for project in MockData.projects {
                    try await Task.sleep(for: .milliseconds(120))
                    visited += 40
                    found += 1
                    bytes += project.reclaimableBytes
                    continuation.yield(.progress(ScanProgress(
                        directoriesVisited: visited, currentPath: project.url.path,
                        projectsFound: found, bytesFound: bytes)))
                    continuation.yield(.project(project))
                }
                let count = MockData.projects.reduce(0) { $0 + $1.candidates.count }
                continuation.yield(.finished(ScanSummary(
                    projectCount: found, candidateCount: count, totalBytes: bytes,
                    startedAt: started, finishedAt: Date())))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct MockCacheScanner: CacheScanning {
    func scanCaches() async -> [CacheGroup] {
        try? await Task.sleep(for: .milliseconds(500))
        return MockData.cacheGroups
    }
}

struct MockSafety: SafetyEvaluating {
    func evaluate(_ candidates: [Candidate], scanRoots: [URL]) async -> [Candidate.ID: SafetyVerdict] {
        var result: [Candidate.ID: SafetyVerdict] = [:]
        for candidate in candidates {
            if candidate.url.path.contains("/client-portal/") {
                result[candidate.id] = .blocked("Inside a protected path (client work).")
            } else if candidate.risk == .danger {
                result[candidate.id] = .warning("May contain files that cannot be regenerated.")
            } else {
                result[candidate.id] = .allowed
            }
        }
        return result
    }
}

struct MockCleaner: CleanExecuting {
    func clean(
        _ candidates: [Candidate], mode: DeleteMode, dryRun: Bool,
        progress: @escaping @Sendable (CleanProgress) -> Void
    ) async -> CleanReport {
        let started = Date()
        var items: [CleanItemResult] = []
        var freed: Int64 = 0
        for (index, candidate) in candidates.enumerated() {
            progress(CleanProgress(completed: index, total: candidates.count, currentTitle: candidate.title, freedBytes: freed))
            try? await Task.sleep(for: .milliseconds(250))
            if dryRun {
                items.append(CleanItemResult(candidate: candidate, status: .dryRun, freedBytes: candidate.sizeBytes))
            } else if candidate.title == "Temp" {
                items.append(CleanItemResult(candidate: candidate, status: .failed, message: "Operation not permitted"))
            } else {
                freed += candidate.sizeBytes
                let trash = mode == .trash ? MockData.home.appendingPathComponent(".Trash/\(candidate.title)") : nil
                items.append(CleanItemResult(candidate: candidate, status: .cleaned, freedBytes: candidate.sizeBytes, trashURL: trash))
            }
        }
        progress(CleanProgress(completed: candidates.count, total: candidates.count, currentTitle: "", freedBytes: freed))
        return CleanReport(startedAt: started, finishedAt: Date(), mode: mode, dryRun: dryRun, items: items)
    }

    func putBack(_ items: [CleanItemResult]) async -> [CleanItemResult] {
        try? await Task.sleep(for: .milliseconds(400))
        return items.map { item in
            var copy = item
            copy.status = .skipped
            copy.message = "Put back"
            return copy
        }
    }
}

actor MockJournal: CleanJournaling {
    private var stored: [CleanReport] = MockJournal.seed()

    private static func seed() -> [CleanReport] {
        let candidates = MockData.projects.flatMap(\.candidates)
        func report(daysAgo: Double, mode: DeleteMode, slice: Range<Int>) -> CleanReport {
            let date = Date().addingTimeInterval(-daysAgo * 86_400)
            let items = candidates[slice].map {
                CleanItemResult(
                    candidate: $0, status: .cleaned, freedBytes: $0.sizeBytes,
                    trashURL: mode == .trash ? MockData.home.appendingPathComponent(".Trash/\($0.title)") : nil)
            }
            return CleanReport(startedAt: date, finishedAt: date.addingTimeInterval(12), mode: mode, dryRun: false, items: items)
        }
        return [
            report(daysAgo: 2, mode: .trash, slice: 0..<3),
            report(daysAgo: 11, mode: .permanent, slice: 5..<9),
            report(daysAgo: 40, mode: .permanent, slice: 12..<14),
        ]
    }

    func append(_ report: CleanReport) async throws { stored.insert(report, at: 0) }
    func reports() async throws -> [CleanReport] { stored }
    func lifetimeFreedBytes() async throws -> Int64 { stored.reduce(0) { $0 + $1.freedBytes } }
}

struct MockSecretFinder: SecretFinding {
    func findSecrets(_ options: VaultCollectOptions) async throws -> [SecretFile] {
        try await Task.sleep(for: .milliseconds(700))
        return MockData.secrets
    }
}

struct MockVaultExporter: VaultExporting {
    func export(_ request: VaultExportRequest) async throws -> VaultExportResult {
        try await Task.sleep(for: .milliseconds(900))
        let entries = request.files.map {
            VaultManifestEntry(
                vaultPath: $0.vaultPath, sourcePath: $0.sourceURL.path, sha256: String(repeating: "ab12", count: 16),
                sizeBytes: $0.sizeBytes, modified: $0.modified, collectedAt: Date(), reason: $0.reason)
        }
        let manifest = VaultManifest(createdAt: Date(), hostName: "demo-mac", entries: entries)
        return VaultExportResult(
            outputURL: request.destination, manifest: manifest,
            copiedCount: max(entries.count - 1, 0), unchangedCount: min(entries.count, 1))
    }
}

struct MockVaultRestorer: VaultRestoring {
    private func manifest() -> VaultManifest {
        let entries = MockData.secrets.map {
            VaultManifestEntry(
                vaultPath: $0.vaultPath, sourcePath: $0.sourceURL.path, sha256: String(repeating: "cd34", count: 16),
                sizeBytes: $0.sizeBytes, modified: $0.modified, collectedAt: Date().addingTimeInterval(-86_400 * 5),
                reason: $0.reason, gitRemoteURL: $0.git?.remoteURL, gitBranch: "main", pathInRepository: $0.pathInRepository)
        }
        return VaultManifest(createdAt: Date().addingTimeInterval(-86_400 * 5), hostName: "demo-mac", entries: entries)
    }

    func open(_ vaultURL: URL, password: String?) async throws -> OpenedVault {
        try await Task.sleep(for: .milliseconds(500))
        if vaultURL.pathExtension == "dmg", (password ?? "").isEmpty {
            throw MockError("A password is required for encrypted images.")
        }
        return OpenedVault(manifest: manifest(), root: vaultURL)
    }

    func close(_ vault: OpenedVault) async {}

    func planRestore(_ vault: OpenedVault, strategy: RestoreStrategy) async throws -> [RestoreAction] {
        try await Task.sleep(for: .milliseconds(400))
        return vault.manifest.entries.enumerated().map { index, entry in
            RestoreAction(
                entry: entry, vaultFileURL: vault.root.appendingPathComponent(entry.vaultPath),
                destinationURL: URL(fileURLWithPath: entry.sourcePath),
                destinationExists: index % 3 == 0, identical: index % 6 == 0)
        }
    }

    func restore(_ actions: [RestoreAction], overwrite: Bool) async throws -> RestoreResult {
        try await Task.sleep(for: .milliseconds(600))
        var result = RestoreResult()
        for action in actions {
            if action.identical || (action.destinationExists && !overwrite) {
                result.skipped.append(action.entry.vaultPath)
            } else {
                result.restored.append(action.entry.vaultPath)
            }
        }
        return result
    }
}

struct MockError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
