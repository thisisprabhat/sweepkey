import CleanerKit
import Foundation
import Observation

enum ScanState: Equatable {
    case idle
    case scanning(ScanProgress)
    case done(ScanSummary)

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }
}

enum CleanPhase {
    case idle
    case confirming
    case running(CleanProgress)
    case finished(CleanReport)
}

/// App-wide state. Service calls are `async` methods spread over feature extensions.
@Observable @MainActor
final class AppModel {
    @ObservationIgnored let services: AppServices

    var settings: CleanerSettings {
        didSet { persistSettings() }
    }

    // Scan
    var scanState: ScanState = .idle
    var projects: [Project] = []
    var cacheGroups: [CacheGroup] = []
    var scanError: String?
    @ObservationIgnored var scanTask: Task<Void, Never>?

    // Selection and safety
    var selection: Set<Candidate.ID> = []
    var verdicts: [Candidate.ID: SafetyVerdict] = [:]

    // Filters
    var searchText = ""
    var ecosystemFilter: String?
    var riskFilter: RiskLevel?
    var minSizeMB = 0
    var staleOnly = false

    // UI
    var showInspector = false
    var inspectedID: String?

    // Clean flow
    var cleanPhase: CleanPhase = .idle
    var cleanMode: DeleteMode = .permanent
    var isCleanSheetPresented = false

    // History
    var reports: [CleanReport] = []
    var lifetimeFreedBytes: Int64 = 0
    var putBackState: [UUID: String] = [:]

    // Vault
    var vaultOptions: VaultCollectOptions
    var findings: [SecretFile] = []
    var findingsSelection: Set<SecretFile.ID> = []
    var isFindingSecrets = false
    var hasSearchedSecrets = false
    var exportState: ExportState = .idle
    var openedVault: OpenedVault?
    var restoreStrategy: RestoreStrategy = .originalPaths
    var restoreActions: [RestoreAction] = []
    var restoreSelection: Set<RestoreAction.ID> = []
    var restoreOverwrite = false
    var restoreResult: RestoreResult?
    var isRestoring = false

    var lastError: String?

    init(services: AppServices = .preview) {
        self.services = services
        let loaded = services.settingsStore.load()
        settings = loaded
        cleanMode = loaded.defaultDeleteMode
        vaultOptions = VaultCollectOptions(
            roots: loaded.scanRoots, excludedPaths: loaded.excludedPaths,
            extraPatterns: loaded.vault.extraPatterns, alwaysCollect: loaded.vault.alwaysCollect,
            includeUncommittedWork: loaded.vault.includeUncommittedWork, scanContents: loaded.vault.scanContents)
    }

    private func persistSettings() {
        do { try services.settingsStore.save(settings) } catch { lastError = error.localizedDescription }
    }

    // MARK: Rules

    func isRuleEnabled(_ rule: Rule) -> Bool {
        settings.ruleOverrides[rule.id] ?? rule.enabledByDefault
    }

    func setRule(_ rule: Rule, enabled: Bool) {
        settings.ruleOverrides[rule.id] = enabled
    }

    var allRules: [Rule] { services.ruleCatalog.rules() + settings.customRules }

    // MARK: Project actions

    func isPinned(_ project: Project) -> Bool { settings.pinnedProjects.contains(project.url) }

    func togglePin(_ project: Project) {
        if let index = settings.pinnedProjects.firstIndex(of: project.url) {
            settings.pinnedProjects.remove(at: index)
        } else {
            settings.pinnedProjects.append(project.url)
        }
    }

    func exclude(_ project: Project) {
        if !settings.excludedPaths.contains(project.url) { settings.excludedPaths.append(project.url) }
        selection.subtract(project.candidates.map(\.id))
        projects.removeAll { $0.id == project.id }
    }
}
