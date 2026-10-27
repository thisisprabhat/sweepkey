import CleanerKit
import Foundation

struct SafeCleanOutcome {
    var report: CleanReport?
    /// Candidates the safety guard blocked (or returned no verdict for).
    var blockedCount = 0
    var error: String?

    var summary: String {
        if let error { return error }
        guard let report else { return "Nothing safe to clean." }
        let freed = ByteCountFormatter.string(fromByteCount: report.freedBytes, countStyle: .file)
        let cleaned = report.items.filter { $0.status == .cleaned || $0.status == .dryRun }.count
        let verb = report.dryRun ? "Would free" : "Freed"
        var text = "\(verb) \(freed) from \(cleaned) item(s)."
        if blockedCount > 0 { text += " \(blockedCount) blocked by safety checks." }
        return text
    }
}

extension AppModel {
    /// What unattended paths may clean: `.safe` artifacts of stale projects, never global caches.
    var safeCleanCandidates: [Candidate] {
        SafeCleanSelection.candidates(projects: projects)
    }

    /// Waits for any in-flight scan, including ones started outside `scanTask` (scheduler, intents).
    func waitForScan() async {
        while scanState.isScanning { try? await Task.sleep(for: .milliseconds(200)) }
    }

    /// Loads the cached scan, or scans, when there are no results yet. Waits for a running scan.
    func ensureScanned() async {
        await waitForScan()
        if projects.isEmpty && cacheGroups.isEmpty {
            await loadCachedScan()
            if projects.isEmpty && cacheGroups.isEmpty && !settings.scanRoots.isEmpty {
                scanGeneration += 1
                await runScan(generation: scanGeneration)
            }
        }
    }

    /// Cleans `candidates` through the same safety path as the GUI, but stricter: SafetyGuard
    /// evaluation with the strict partition (a warning, such as an open project, or a missing
    /// verdict is blocked), stale-project `.safe` artifacts only, vault export first when the
    /// setting asks for it, and a journal entry for real runs. Never touches the user's selection.
    func cleanEligible(_ candidates: [Candidate], dryRun: Bool) async -> SafeCleanOutcome {
        let state = AutomationState.shared
        if state.isCleaning { return SafeCleanOutcome(error: "Another clean is already running.") }
        if case .running = cleanPhase { return SafeCleanOutcome(error: "Another clean is already running.") }
        state.isCleaning = true
        defer { state.isCleaning = false }

        let safeOnly = candidates.filter { $0.risk == .safe && $0.kind == .projectArtifact }
        guard !safeOnly.isEmpty else { return SafeCleanOutcome() }
        await evaluateVerdicts(for: safeOnly)
        let (items, blocked) = AppLogic.partitionStrict(safeOnly, verdicts: verdicts)
        guard !items.isEmpty else { return SafeCleanOutcome(blockedCount: blocked.count) }

        if settings.requireVaultBeforeClean, !dryRun {
            if let failure = await exportSecretsBeforeClean(for: items) {
                return SafeCleanOutcome(blockedCount: blocked.count, error: "Clean aborted: \(failure)")
            }
        }
        let report = await services.cleaner.clean(items, mode: settings.defaultDeleteMode, dryRun: dryRun) { _ in }
        if !dryRun {
            do { try await services.journal.append(report) } catch { lastError = error.localizedDescription }
            let cleaned = Set(report.items.filter { $0.status == .cleaned }.map(\.candidate.id))
            selection.subtract(cleaned)
            removeCandidates(cleaned)
            diskRefreshToken += 1
            await persistScanCache()
            await loadJournal()
        }
        return SafeCleanOutcome(report: report, blockedCount: blocked.count)
    }

    /// Cleans every eligible safe candidate. Callers must have obtained confirmation first.
    func cleanSafeItems(dryRun: Bool) async -> SafeCleanOutcome {
        await ensureScanned()
        let outcome = await cleanEligible(safeCleanCandidates, dryRun: dryRun)
        AutomationState.shared.lastActionMessage = outcome.summary
        return outcome
    }

    /// Selects the eligible safe items and shows the clean confirmation sheet. Never deletes.
    /// Used by the low-space notification action, so it applies the strict partition up front:
    /// items with a warning (an open project) are not pre-selected.
    func presentSafeCleanSheet() async {
        await ensureScanned()
        await evaluateVerdicts(for: safeCleanCandidates)
        let eligible = AppLogic.partitionStrict(safeCleanCandidates, verdicts: verdicts).cleanable
        guard !eligible.isEmpty else {
            lastError = "There are no safe items to clean right now."
            return
        }
        selection = Set(eligible.map(\.id))
        await beginClean()
    }

    /// Snapshots all current secrets to the vault (folder format only).
    func snapshotVault() async throws -> VaultExportResult? {
        let found = try await collectSecrets(currentVaultCollectOptions)
        guard !found.files.isEmpty else { return nil }
        return try await services.vaultExporter.export(VaultExportRequest(
            files: found.files, destination: settings.vaultFolderDestination, format: .folder,
            keepVersions: settings.vault.keepVersions))
    }

    // MARK: Path scans

    /// Scans only the given folders (used by `cleaner://scan` and the Services menu). Replaces the
    /// shown results with them; does not add scan roots and does not overwrite the saved scan cache.
    func scanPaths(_ urls: [URL]) async {
        let roots = AppLogic.directories(from: urls)
        guard !roots.isEmpty, !scanState.isScanning else { return }
        scanGeneration += 1
        let token = scanGeneration
        scanError = nil
        projects = []
        selection = []
        scanState = .scanning(ScanProgress(directoriesVisited: 0, currentPath: "", projectsFound: 0, bytesFound: 0))
        let found = await collectProjects(in: roots) { [weak self] progress in
            guard let self, token == self.scanGeneration else { return }
            self.scanState = .scanning(progress)
        }
        guard token == scanGeneration else { return }
        projects = found.projects
        scanError = found.failure
        scanState = .done(ScanSummary(
            projectCount: projects.count, candidateCount: projects.reduce(0) { $0 + $1.candidates.count },
            totalBytes: projects.reduce(0) { $0 + $1.reclaimableBytes }, startedAt: Date(), finishedAt: Date()))
    }

    /// Background rescan of only the given directories, merged into the current results. Leaves
    /// `scanState` alone so the UI does not flicker, and skips when a full scan is running.
    /// Returns true only when the results were actually merged; a cancelled or failed scan merges
    /// nothing (so no project is dropped) and the caller should retry later.
    @discardableResult
    func rescanMerging(_ affected: [URL]) async -> Bool {
        guard !scanState.isScanning, !affected.isEmpty else { return false }
        let roots = AppLogic.resolve(affected).filter { FileManager.default.fileExists(atPath: $0.path) }
        let found = await collectProjects(in: roots, progress: nil)
        guard !Task.isCancelled, found.failure == nil, !scanState.isScanning else { return false }
        let all = AppLogic.resolve(affected)
        projects.removeAll { project in
            all.contains { project.url == $0 || project.url.isDescendant(of: $0) }
        }
        projects.append(contentsOf: found.projects)
        projects.sort { $0.reclaimableBytes > $1.reclaimableBytes }
        selection = selection.filter { id in allCandidates.contains { $0.id == id } }
        await persistScanCache()
        return true
    }

    private func collectProjects(
        in roots: [URL], progress: (@MainActor (ScanProgress) -> Void)?
    ) async -> (projects: [Project], failure: String?) {
        let options = ScanOptions(
            roots: roots, excludedPaths: AppLogic.resolve(settings.excludedPaths),
            ruleOverrides: settings.ruleOverrides, customRules: settings.customRules,
            staleAfterDays: settings.staleAfterDays)
        var found: [Project] = []
        var failure: String?
        do {
            for try await event in services.scanner.scan(options) {
                switch event {
                case .progress(let value): progress?(value)
                case .project(let project): found.append(project)
                case .finished: break
                }
            }
        } catch {
            failure = error.localizedDescription
        }
        return (found, failure)
    }
}

extension AppModel {
    /// One shared model for the window, menu bar, intents and URL handlers.
    static let shared = AppModel(services: .live)
}
