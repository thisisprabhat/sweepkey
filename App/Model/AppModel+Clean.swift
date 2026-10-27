import CleanerKit
import Foundation

extension AppModel {
    var blockedSelected: [Candidate] {
        selectedCandidates.filter { !(verdicts[$0.id]?.isAllowed ?? false) }
    }

    var cleanableSelected: [Candidate] {
        // A candidate without a verdict is never cleanable.
        selectedCandidates.filter { verdicts[$0.id]?.isAllowed ?? false }
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
        let items = cleanableSelected
        guard !items.isEmpty else { return }
        cleanPhase = .running(CleanProgress(completed: 0, total: items.count, currentTitle: "", freedBytes: 0))
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
            await loadJournal()
        }
        cleanPhase = .finished(report)
    }

    func dismissClean() {
        isCleanSheetPresented = false
        cleanPhase = .idle
    }

    private func removeCandidates(_ ids: Set<Candidate.ID>) {
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
