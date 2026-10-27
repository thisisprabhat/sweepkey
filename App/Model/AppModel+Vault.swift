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
            findings = try await services.secrets.findSecrets(vaultOptions)
            findingsSelection = Set(findings.map(\.id))
            hasSearchedSecrets = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    var selectedFindings: [SecretFile] { findings.filter { findingsSelection.contains($0.id) } }

    func exportVault(format: VaultExportFormat, destination: URL, password: String?) async {
        exportState = .running
        let request = VaultExportRequest(
            files: selectedFindings, destination: destination, format: format,
            password: password, keepVersions: settings.vault.keepVersions)
        do {
            exportState = .done(try await services.vaultExporter.export(request))
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }

    // MARK: Restore

    func openVault(_ url: URL, password: String?) async -> Bool {
        do {
            if let current = openedVault { await services.vaultRestorer.close(current) }
            openedVault = try await services.vaultRestorer.open(url, password: password)
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
            restoreActions = try await services.vaultRestorer.planRestore(vault, strategy: restoreStrategy)
            restoreSelection = Set(restoreActions.filter { !$0.identical }.map(\.id))
        } catch {
            lastError = error.localizedDescription
        }
    }

    func runRestore() async {
        isRestoring = true
        defer { isRestoring = false }
        let chosen = restoreActions.filter { restoreSelection.contains($0.id) }
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
        restoreResult = nil
    }
}
