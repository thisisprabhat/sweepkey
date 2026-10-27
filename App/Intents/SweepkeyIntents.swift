import AppIntents
import SweepkeyKit
import Foundation

private func sizeText(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

struct ScanProjectsIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan Projects"
    static let description = IntentDescription("Scans your project folders and reports how much can be reclaimed.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = AppModel.shared
        if model.scanState.isScanning { await model.waitForScan() } else {
            model.scanGeneration += 1
            await model.runScan(generation: model.scanGeneration)
        }
        let text = "\(model.projects.count) project(s), \(sizeText(model.reclaimableBytes)) reclaimable."
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct CleanStaleArtifactsIntent: AppIntent {
    static let title: LocalizedStringResource = "Clean Stale Artifacts"
    static let description = IntentDescription(
        "Cleans safe artifacts of stale projects (never global caches). Dry run by default; a real run asks for confirmation.")

    @Parameter(title: "Dry Run", default: true)
    var dryRun: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = AppModel.shared
        await model.ensureScanned()
        let items = model.safeCleanCandidates
        if !dryRun {
            try await requestConfirmation(
                actionName: .custom(acceptLabel: "Clean", acceptAlternatives: [], denyLabel: "Cancel", denyAlternatives: [], destructive: true),
                dialog: IntentDialog(stringLiteral:
                    "Clean \(items.count) safe item(s), \(sizeText(items.reduce(0) { $0 + $1.sizeBytes }))?"))
        }
        // Exactly the items that were confirmed, not a recomputed list.
        let outcome = await model.cleanEligible(items, dryRun: dryRun)
        AutomationState.shared.lastActionMessage = outcome.summary
        return .result(value: outcome.summary, dialog: IntentDialog(stringLiteral: outcome.summary))
    }
}

struct SnapshotSecretsIntent: AppIntent {
    static let title: LocalizedStringResource = "Snapshot Secrets"
    static let description = IntentDescription("Copies un-committed secret files into the vault folder.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text: String
        do {
            if let result = try await AppModel.shared.snapshotVault() {
                text = "Vault snapshot saved: \(result.copiedCount) copied, \(result.unchangedCount) unchanged."
            } else {
                text = "No secret files were found."
            }
        } catch {
            text = "Snapshot failed: \(error.localizedDescription)"
        }
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct FreeUpSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Free Up Space"
    static let description = IntentDescription(
        "Cleans safe artifacts of stale projects, largest first, until the requested amount is reclaimed.")

    @Parameter(title: "Gigabytes", default: 5, inclusiveRange: (1, 1000))
    var gigabytes: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = AppModel.shared
        await model.ensureScanned()
        let target = Int64(gigabytes) * 1_000_000_000
        let items = SafeCleanSelection.largestFirst(upTo: target, from: model.safeCleanCandidates)
        guard !items.isEmpty else {
            let text = "Nothing safe to clean."
            return .result(value: text, dialog: IntentDialog(stringLiteral: text))
        }
        // Always confirm: this intent has no dry-run parameter.
        try await requestConfirmation(
            actionName: .custom(acceptLabel: "Clean", acceptAlternatives: [], denyLabel: "Cancel", denyAlternatives: [], destructive: true),
            dialog: IntentDialog(stringLiteral:
                "Clean \(items.count) safe item(s), \(sizeText(items.reduce(0) { $0 + $1.sizeBytes })), to free about \(gigabytes) GB?"))
        let outcome = await model.cleanEligible(items, dryRun: false)
        AutomationState.shared.lastActionMessage = outcome.summary
        return .result(value: outcome.summary, dialog: IntentDialog(stringLiteral: outcome.summary))
    }
}

struct SweepkeyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ScanProjectsIntent(), phrases: ["Scan projects with \(.applicationName)"],
                    shortTitle: "Scan Projects", systemImageName: "magnifyingglass")
        AppShortcut(intent: CleanStaleArtifactsIntent(), phrases: ["Clean stale artifacts with \(.applicationName)"],
                    shortTitle: "Clean Stale Artifacts", systemImageName: "sparkles")
        AppShortcut(intent: SnapshotSecretsIntent(), phrases: ["Snapshot secrets with \(.applicationName)"],
                    shortTitle: "Snapshot Secrets", systemImageName: "lock.shield")
        AppShortcut(intent: FreeUpSpaceIntent(), phrases: ["Free up space with \(.applicationName)"],
                    shortTitle: "Free Up Space", systemImageName: "internaldrive")
    }
}
