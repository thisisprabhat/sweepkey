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

    /// Starts the clean from the confirmation sheet and keeps the task so it can be cancelled.
    /// `acknowledged` lists the warning/danger items the user ticked off in the sheet.
    func startClean(dryRun: Bool, acknowledged: Set<Candidate.ID>) {
        guard cleanTask == nil else { return }
        cleanTask = Task { [weak self] in
            await self?.runClean(dryRun: dryRun, acknowledged: acknowledged)
            self?.cleanTask = nil
        }
    }

    /// Cancels a running GUI clean. Items not yet processed are reported as cancelled, and the
    /// partial run is still journaled.
    func cancelClean() {
        cleanTask?.cancel()
        if case .running(let progress) = cleanPhase {
            var cancelling = progress
            cancelling.currentTitle = "Cancelling…"
            cleanPhase = .running(cancelling)
        }
    }

    func runClean(dryRun: Bool, acknowledged: Set<Candidate.ID> = []) async {
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
        if !dryRun {
            // A warning that appeared after the sheet was shown was never acknowledged: review again.
            let unacknowledged = items.filter {
                AppLogic.needsAcknowledgement($0, verdict: verdicts[$0.id]) && !acknowledged.contains($0.id)
            }
            if !unacknowledged.isEmpty {
                lastError = "The safety status of \(unacknowledged.count) item(s) changed. Review and confirm again."
                cleanPhase = .confirming
                return
            }
        }
        cleanPhase = .running(CleanProgress(completed: 0, total: items.count, currentTitle: "", freedBytes: 0))
        vaultBeforeCleanWarnings = []
        cleanFreeSpace = nil
        let freeBefore = DiskInfo.current()?.freeBytes

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
                guard let self, case .running(let current) = self.cleanPhase else { return }
                var next = progress
                if self.cleanTask?.isCancelled == true { next.currentTitle = current.currentTitle }
                self.cleanPhase = .running(next)
            }
        }
        if !dryRun {
            do { try await services.journal.append(report) } catch { lastError = error.localizedDescription }
            let cleaned = Set(report.items.filter { $0.status == .cleaned }.map(\.candidate.id))
            selection.subtract(cleaned)
            removeCandidates(cleaned)
            diskRefreshToken += 1
            if let freeBefore, let after = DiskInfo.current()?.freeBytes {
                cleanFreeSpace = FreeSpaceDelta(before: freeBefore, after: after)
            }
            await persistScanCache()
            await loadJournal()
            // Spec §E: rescan what was cleaned, in the background, so the lists reflect the disk.
            let roots = AppLogic.affectedProjectRoots(report)
            if !roots.isEmpty {
                Task { [weak self] in await self?.rescanMerging(roots) }
            }
        }
        cleanPhase = .finished(report)
    }

    /// Vault collection options from the current settings, with resolved roots.
    var currentVaultCollectOptions: VaultCollectOptions { settings.vaultCollectOptions() }

    /// Collects and exports (folder format) the secrets of the projects being cleaned.
    /// Returns an error description on failure, nil on success.
    func exportSecretsBeforeClean(for items: [Candidate]) async -> String? {
        do {
            let outcome = try await VaultBeforeClean.run(
                candidates: items, settings: settings,
                collect: { [self] options in try await collectSecrets(options) },
                exporter: services.vaultExporter)
            vaultBeforeCleanWarnings = outcome.warnings
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
