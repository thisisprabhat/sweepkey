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
    /// Bumped by every scan start and cancel; a scan only writes state while its token is current.
    @ObservationIgnored var scanGeneration = 0
    /// Bumped after a clean so disk gauges re-read free space.
    var diskRefreshToken = 0

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
    var puttingBack: Set<UUID> = []
    var putBackDone: Set<UUID> = []

    // Vault
    var vaultOptions: VaultCollectOptions
    var findings: [SecretFile] = []
    var findingsSelection: Set<SecretFile.ID> = []
    var isFindingSecrets = false
    var hasSearchedSecrets = false
    var vaultWarnings: [String] = []
    /// Finder warnings from the vault-before-clean pass; shown with the clean result.
    var vaultBeforeCleanWarnings: [String] = []
    var exportState: ExportState = .idle
    var openedVault: OpenedVault?
    var restoreStrategy: RestoreStrategy = .originalPaths
    var restoreActions: [RestoreAction] = []
    var restoreSelection: Set<RestoreAction.ID> = []
    var restoreOverwrite = false
    var restoreResult: RestoreResult?
    var isRestoring = false

    var lastError: String?

    /// Set to jump straight to an onboarding step (e.g. Full Disk Access from the Dashboard banner).
    var onboardingStartStep = 0

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

    /// Adds dropped or opened folders as scan roots (resolved, de-duplicated).
    func addScanRoots(_ urls: [URL]) {
        let dirs = AppLogic.directories(from: urls)
        let existing = Set(AppLogic.resolve(settings.scanRoots).map(\.path))
        let new = dirs.filter { !existing.contains($0.path) }
        guard !new.isEmpty else { return }
        settings.scanRoots.append(contentsOf: new)
        if !scanState.isScanning { scan() }
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
