import SweepkeyKit
import Foundation

/// Secret finder that also reports repositories whose git queries failed.
protocol WarningSecretFinding: SecretFinding {
    func findSecretsWithWarnings(_ options: VaultCollectOptions) async throws -> (files: [SecretFile], warnings: [String])
}

struct LiveSecretFinder: WarningSecretFinding {
    private let finder = SecretFinder()

    func findSecrets(_ options: VaultCollectOptions) async throws -> [SecretFile] {
        try await finder.findSecrets(options)
    }

    func findSecretsWithWarnings(_ options: VaultCollectOptions) async throws -> (files: [SecretFile], warnings: [String]) {
        try await finder.findSecretsWithWarnings(options)
    }
}

/// The bundled rule set (`rules.json`).
struct LiveRuleCatalog: RuleCatalog {
    private let loaded: [Rule]
    init() { loaded = (try? RuleSet.bundled()) ?? [] }
    func rules() -> [Rule] { loaded }
}

extension AppServices {
    static func makeSafety(pinned: [URL]) -> any SafetyEvaluating {
        SafetyGuard(
            gitShell: ProcessShellRunner(), pinnedProjects: AppLogic.resolve(pinned),
            activeDirectories: { await ActiveProjectDetector.currentWorkingDirectories() })
    }

    /// Real SweepkeyKit services. `#Preview` keeps using `.preview`.
    static let live = AppServices(
        scanner: ProjectScanner(),
        caches: GlobalCacheScanner(),
        safety: makeSafety(pinned: []),
        cleaner: CleanExecutor(),
        journal: JSONJournal(fileURL: AppRuntime.journalFile),
        secrets: LiveSecretFinder(),
        vaultExporter: VaultExporter(),
        vaultRestorer: VaultRestorer(),
        settingsStore: SettingsStore(fileURL: AppRuntime.settingsFile),
        ruleCatalog: LiveRuleCatalog(),
        scanCache: ScanCache(url: AppRuntime.scanCacheFile),
        safetyFor: { makeSafety(pinned: $0) })
}
