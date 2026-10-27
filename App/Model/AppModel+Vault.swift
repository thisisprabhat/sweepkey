import CleanerKit
import Foundation

enum ExportState {
    case idle
    case running
    case done(VaultExportResult)
    case failed(String)
}

extension AppModel {
    func findSecrets() async {
        isFindingSecrets = true
        defer { isFindingSecrets = false }
        do {
            let result = try await collectSecrets(vaultOptions)
            findings = result.files
            vaultWarnings = result.warnings
            findingsSelection = Set(findings.map(\.id))
            hasSearchedSecrets = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// What the Vault screen collects: the current settings (read every time, so a first-launch
    /// setup or a later settings change is picked up) with the session overrides on top. Resolved.
    var vaultOptions: VaultCollectOptions { vaultOverrides.applied(to: settings) }

    /// Uses the warning-aware finder when the services provide one.
    func collectSecrets(_ options: VaultCollectOptions) async throws -> (files: [SecretFile], warnings: [String]) {
        if let finder = services.secrets as? any WarningSecretFinding {
            return try await finder.findSecretsWithWarnings(options)
        }
        return (try await services.secrets.findSecrets(options), [])
    }

    private var resolvedStrategy: RestoreStrategy {
        if case .matchGitRemote(let roots) = restoreStrategy { return .matchGitRemote(searchRoots: AppLogic.resolve(roots)) }
        return restoreStrategy
    }

    var selectedFindings: [SecretFile] { findings.filter { findingsSelection.contains($0.id) } }

    func exportVault(format: VaultExportFormat, destination: URL, password: String?, rememberInKeychain: Bool = false) async {
        exportState = .running
        let request = VaultExportRequest(
            files: selectedFindings, destination: destination.standardizedFileURL.resolvingSymlinksInPath(), format: format,
            password: password, keepVersions: settings.vault.keepVersions)
        do {
            let result = try await services.vaultExporter.export(request)
            exportState = .done(result)
            if rememberInKeychain, format == .encryptedImage, let password {
                let account = result.outputURL.standardizedFileURL.resolvingSymlinksInPath().path
                do { try VaultKeychain.save(password: password, account: account) } catch {
                    lastError = "The vault was exported, but the password could not be saved to the Keychain: \(error.localizedDescription)"
                }
            }
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }

    // MARK: Restore

    func openVault(_ url: URL, password: String?) async -> Bool {
        do {
            if let current = openedVault { await services.vaultRestorer.close(current) }
            openedVault = try await services.vaultRestorer.open(url.standardizedFileURL.resolvingSymlinksInPath(), password: password)
            restoreResult = nil
            await planRestore()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func planRestore() async {
        guard let vault = openedVault else { return }
        do {
            if let restorer = services.vaultRestorer as? VaultRestorer {
                let plan = try await restorer.planRestoreWithWarnings(vault, strategy: resolvedStrategy)
                restoreActions = plan.actions
                restoreWarnings = plan.warnings
            } else {
                restoreActions = try await services.vaultRestorer.planRestore(vault, strategy: resolvedStrategy)
                restoreWarnings = []
            }
            restoreSelection = Set(restoreActions.filter { !$0.identical }.map(\.id))
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The actions the Restore button would run.
    var chosenRestoreActions: [RestoreAction] { restoreActions.filter { restoreSelection.contains($0.id) } }

    func runRestore() async {
        isRestoring = true
        defer { isRestoring = false }
        let chosen = chosenRestoreActions
        do {
            restoreResult = try await services.vaultRestorer.restore(chosen, overwrite: restoreOverwrite)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func closeVault() async {
        if let vault = openedVault { await services.vaultRestorer.close(vault) }
        openedVault = nil
        restoreActions = []
        restoreWarnings = []
        restoreResult = nil
    }
}
