import CleanerKit
import Foundation

extension AppModel {
    /// Plans a free-up run. Evaluates safety first; a candidate without a verdict is never planned.
    func planFreeUp(targetBytes: Int64) async -> [Candidate] {
        await evaluateVerdicts(for: allCandidates)
        return FreeUpPlanner.plan(target: targetBytes, projects: projects, caches: cacheGroups, verdicts: verdicts)
    }

    /// Selects the plan and opens the normal clean confirmation sheet. Never cleans by itself.
    func reviewForCleaning(_ plan: [Candidate]) {
        selection = Set(plan.map(\.id))
        requestClean()
    }

    func runArchive(
        project: Project, vaultDestination: URL, archiveDirectory: URL?, zip: Bool, acknowledgeRisks: Bool
    ) async -> ArchiveReport {
        // Shares the clean guard with the GUI and automation cleans.
        let automation = AutomationState.shared
        if automation.isCleaning {
            var busy = ArchiveReport()
            busy.steps.append(ArchiveStep(name: "Archive", status: .failed, detail: "Another clean is already running."))
            return busy
        }
        automation.isCleaning = true
        defer { automation.isCleaning = false }

        let recipe = ArchiveRecipe(
            secrets: services.secrets, exporter: services.vaultExporter, cleaner: services.cleaner,
            safety: SafetyBridge(base: services.safetyFor?(settings.pinnedProjects) ?? services.safety,
                                 scanRoots: AppLogic.resolve(settings.scanRoots)))
        let report = await recipe.run(
            project: project, vaultDestination: vaultDestination.standardizedFileURL.resolvingSymlinksInPath(),
            archiveDirectory: archiveDirectory, zip: zip, acknowledgeRisks: acknowledgeRisks,
            collect: currentVaultCollectOptions, layoutRoots: AppLogic.resolve(settings.scanRoots),
            keepVersions: settings.vault.keepVersions)
        let entries = ArchiveJournal.reports(for: report, project: project)
        if !entries.isEmpty {
            for entry in entries {
                do { try await services.journal.append(entry) } catch { lastError = error.localizedDescription }
            }
            diskRefreshToken += 1
            await loadJournal()
        }
        if report.trashedProject {
            projects.removeAll { $0.id == project.id }
        } else if report.freedBytes > 0 {
            let cleaned = Set(project.candidates.map(\.id))
            if let i = projects.firstIndex(where: { $0.id == project.id }) {
                projects[i].candidates.removeAll { cleaned.contains($0.id) }
            }
        }
        if report.trashedProject || report.freedBytes > 0 { await persistScanCache() }
        return report
    }

    func exportMigration(to directory: URL) async throws -> MigrationResult {
        try await MigrationBundle.export(
            roots: AppLogic.resolve(settings.scanRoots), to: directory, secrets: services.secrets,
            exporter: services.vaultExporter, collect: currentVaultCollectOptions,
            keepVersions: settings.vault.keepVersions)
    }
}

/// Evaluates with the user's scan roots, so containment checks match the rest of the app.
private struct SafetyBridge: SafetyEvaluating {
    let base: any SafetyEvaluating
    let scanRoots: [URL]
    func evaluate(_ candidates: [Candidate], scanRoots _: [URL]) async -> [Candidate.ID: SafetyVerdict] {
        await base.evaluate(candidates, scanRoots: scanRoots)
    }
}
