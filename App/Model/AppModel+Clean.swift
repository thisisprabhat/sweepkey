import CleanerKit
import Foundation

extension AppModel {
    var blockedSelected: [Candidate] {
        AppLogic.partition(selectedCandidates, verdicts: verdicts).blocked
    }

    var cleanableSelected: [Candidate] {
        // A candidate without a verdict is never cleanable.
        AppLogic.partition(selectedCandidates, verdicts: verdicts).cleanable
    }

    /// Evaluates safety for the selection, then presents the confirmation sheet.
    func beginClean() async {
        guard !selection.isEmpty, !isCleanSheetPresented else { return }
        await evaluateVerdicts(for: selectedCandidates)
        cleanMode = settings.defaultDeleteMode
        cleanPhase = .confirming
        isCleanSheetPresented = true
    }

    func requestClean() {
        Task { await beginClean() }
    }

    func runClean(dryRun: Bool) async {
        // Two-way guard with automation cleans (menu bar, intents, scheduler).
        let automation = AutomationState.shared
        guard !automation.isCleaning else {
            lastError = "Another clean is already running."
            return
        }
        automation.isCleaning = true
        defer { automation.isCleaning = false }
        // Re-evaluate right before acting: state may have changed since the sheet opened.
        await evaluateVerdicts(for: selectedCandidates)
        let items = cleanableSelected
        guard !items.isEmpty else { return }
        cleanPhase = .running(CleanProgress(completed: 0, total: items.count, currentTitle: "", freedBytes: 0))
        vaultBeforeCleanWarnings = []

        if settings.requireVaultBeforeClean, !dryRun {
            cleanPhase = .running(CleanProgress(
                completed: 0, total: items.count, currentTitle: "Exporting secrets to the vault…", freedBytes: 0))
            if let failure = await exportSecretsBeforeClean(for: items) {
                lastError = "Clean aborted: \(failure)"
                cleanPhase = .confirming
                return
            }
        }

        let report = await services.cleaner.clean(items, mode: cleanMode, dryRun: dryRun) { [weak self] progress in
            Task { @MainActor in
                guard let self, case .running = self.cleanPhase else { return }
                self.cleanPhase = .running(progress)
            }
        }
        if !dryRun {
            do { try await services.journal.append(report) } catch { lastError = error.localizedDescription }
            let cleaned = Set(report.items.filter { $0.status == .cleaned }.map(\.candidate.id))
            selection.subtract(cleaned)
            removeCandidates(cleaned)
            diskRefreshToken += 1
            await persistScanCache()
            await loadJournal()
        }
        cleanPhase = .finished(report)
    }

    /// Vault collection options from the current settings, with resolved roots.
    var currentVaultCollectOptions: VaultCollectOptions {
        VaultCollectOptions(
            roots: AppLogic.resolve(settings.scanRoots), excludedPaths: AppLogic.resolve(settings.excludedPaths),
            extraPatterns: settings.vault.extraPatterns, alwaysCollect: settings.vault.alwaysCollect,
            includeUncommittedWork: settings.vault.includeUncommittedWork, scanContents: settings.vault.scanContents)
    }

    /// Collects and exports (folder format) the secrets of the projects being cleaned.
    /// Returns an error description on failure, nil on success.
    func exportSecretsBeforeClean(for items: [Candidate]) async -> String? {
        let itemIDs = Set(items.map(\.id))
        let affected = projects.filter { project in project.candidates.contains { itemIDs.contains($0.id) } }
            .map { $0.url.standardizedFileURL.resolvingSymlinksInPath() }
        guard !affected.isEmpty else { return nil }
        let options = currentVaultCollectOptions
        do {
            let found = try await collectSecrets(options)
            vaultBeforeCleanWarnings = found.warnings
            let files = found.files.filter { file in
                let source = file.sourceURL.standardizedFileURL.resolvingSymlinksInPath()
                return affected.contains { source.isDescendant(of: $0) }
            }
            guard !files.isEmpty else { return nil }
            let destination = (settings.vault.destination ?? AppPaths.defaultVaultDirectory)
                .standardizedFileURL.resolvingSymlinksInPath()
            _ = try await services.vaultExporter.export(VaultExportRequest(
                files: files, destination: destination, format: .folder, keepVersions: settings.vault.keepVersions))
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func dismissClean() {
        isCleanSheetPresented = false
        cleanPhase = .idle
    }

    func removeCandidates(_ ids: Set<Candidate.ID>) {
        projects = projects.compactMap { project in
            var copy = project
            copy.candidates.removeAll { ids.contains($0.id) }
            return copy.candidates.isEmpty ? nil : copy
        }
        cacheGroups = cacheGroups.compactMap { group in
            var copy = group
            copy.candidates.removeAll { ids.contains($0.id) }
            return copy.candidates.isEmpty ? nil : copy
        }
    }

    // MARK: History

    func loadJournal() async {
        do {
            reports = try await services.journal.reports()
            lifetimeFreedBytes = try await services.journal.lifetimeFreedBytes()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func putBack(_ report: CleanReport) async {
        let items = report.items.filter { $0.status == .cleaned && $0.trashURL != nil }
        guard !puttingBack.contains(report.id) else { return }
        puttingBack.insert(report.id)
        defer { puttingBack.remove(report.id) }
        putBackState[report.id] = "Putting back…"
        let results = await services.cleaner.putBack(items)
        let failed = results.filter { $0.status == .failed }.count
        let restored = results.count - failed
        putBackState[report.id] = failed == 0
            ? "Restored \(restored) item(s) from the Trash."
            : "Restored \(restored) item(s); \(failed) could not be put back."
        if failed == 0 { putBackDone.insert(report.id) }
    }
}
