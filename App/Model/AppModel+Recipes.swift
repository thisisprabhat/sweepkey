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
        let recipe = ArchiveRecipe(
            secrets: services.secrets, exporter: services.vaultExporter, cleaner: services.cleaner,
            safety: SafetyBridge(base: services.safety, scanRoots: settings.scanRoots))
        let report = await recipe.run(
            project: project, vaultDestination: vaultDestination, archiveDirectory: archiveDirectory,
            zip: zip, acknowledgeRisks: acknowledgeRisks)
        if report.trashedProject {
            projects.removeAll { $0.id == project.id }
        } else if report.freedBytes > 0 {
            let cleaned = Set(project.candidates.map(\.id))
            if let i = projects.firstIndex(where: { $0.id == project.id }) {
                projects[i].candidates.removeAll { cleaned.contains($0.id) }
            }
        }
        return report
    }

    func exportMigration(to directory: URL) async throws -> MigrationResult {
        try await MigrationBundle.export(
            roots: settings.scanRoots, to: directory, secrets: services.secrets, exporter: services.vaultExporter)
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
