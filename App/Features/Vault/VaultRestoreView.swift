import CleanerKit
import OSLog
import SwiftUI

struct VaultRestoreView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingEncrypted: URL?
    @State private var password = ""
    @State private var hasSavedPassword = false
    @State private var confirmingRestore = false
    private static let log = Logger(subsystem: "com.prabhatkumar.Cleaner", category: "keychain")

    private enum StrategyKind: Hashable { case original, gitRemote }

    var body: some View {
        @Bindable var model = model
        Group {
            if let vault = model.openedVault {
                restorePlan(vault)
            } else {
                EmptyStateView("Restore a vault", symbolName: "arrow.uturn.backward.circle",
                               message: "Open a vault folder, archive or encrypted image to put files back.") {
                    Button("Open Vault…", systemImage: "folder") { open() }
                        .buttonStyle(.glassProminent)
                }
            }
        }
        .alert("Vault Password", isPresented: Binding(
            get: { pendingEncrypted != nil }, set: { if !$0 { pendingEncrypted = nil } })) {
            SecureField("Password", text: $password)
            Button("Open") {
                if let url = pendingEncrypted { Task { _ = await model.openVault(url, password: password) } }
                password = ""
                pendingEncrypted = nil
            }
            if hasSavedPassword {
                Button("Forget Saved Password", role: .destructive) {
                    if let url = pendingEncrypted {
                        VaultKeychain.delete(account: url.standardizedFileURL.resolvingSymlinksInPath().path)
                    }
                    hasSavedPassword = false
                    password = ""
                    pendingEncrypted = nil
                }
            }
            Button("Cancel", role: .cancel) { password = ""; pendingEncrypted = nil }
        } message: {
            Text("Enter the password for this encrypted image.")
        }
    }

    private func open() {
        guard let url = Panels.chooseVault() else { return }
        if url.pathExtension.lowercased() == "dmg" {
            // A saved password is unlocked with Touch ID; cancelling falls back to typing it.
            let account = url.standardizedFileURL.resolvingSymlinksInPath().path
            Task {
                let outcome = await Task.detached { () -> Result<String?, Error> in
                    Result { try VaultKeychain.load(account: account) }
                }.value
                switch outcome {
                case .success(let saved):
                    if let saved, await model.openVault(url, password: saved) { return }
                case .failure(let error):
                    Self.log.error("Keychain read failed: \(error.localizedDescription, privacy: .public)")
                }
                hasSavedPassword = VaultKeychain.exists(account: account)
                pendingEncrypted = url
            }
        } else {
            Task { _ = await model.openVault(url, password: nil) }
        }
    }

    private func restorePlan(_ vault: OpenedVault) -> some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            Form {
                LabeledContent("Vault") {
                    Text("\(vault.manifest.entries.count) files from \(vault.manifest.hostName)")
                }
                Picker("Restore to", selection: Binding(
                    get: { if case .originalPaths = model.restoreStrategy { StrategyKind.original } else { StrategyKind.gitRemote } },
                    set: { kind in
                        model.restoreStrategy = kind == .original
                            ? .originalPaths : .matchGitRemote(searchRoots: model.settings.scanRoots)
                        Task { await model.planRestore() }
                    })) {
                    Text("Original paths").tag(StrategyKind.original)
                    Text("Match by git remote").tag(StrategyKind.gitRemote)
                }
                .pickerStyle(.segmented)
                if case .matchGitRemote(let roots) = model.restoreStrategy {
                    URLListEditor(title: "Search roots", panelMessage: "Folders containing your cloned repositories",
                                  urls: Binding(
                                    get: { roots },
                                    set: { model.restoreStrategy = .matchGitRemote(searchRoots: $0) }))
                    Button("Re-plan") { Task { await model.planRestore() } }
                }
                Toggle("Overwrite files that already exist", isOn: $model.restoreOverwrite)
            }
            .formStyle(.grouped)
            .frame(maxHeight: 260)
            if !model.restoreWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.restoreWarnings, id: \.self) { Text($0).font(.caption) }
                }
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 6)
            }
            RestoreActionsTable()
            if let result = model.restoreResult { resultBar(result) }
            HStack {
                Button("Close Vault") { Task { await model.closeVault() } }
                Spacer()
                Button("Restore \(model.restoreSelection.count) Files", systemImage: "arrow.uturn.backward") {
                    confirmingRestore = true
                }
                .buttonStyle(.glassProminent)
                .disabled(model.restoreSelection.isEmpty || model.isRestoring)
            }
            .padding(12)
        }
        .confirmationDialog("Restore \(model.chosenRestoreActions.count) files?", isPresented: $confirmingRestore) {
            Button("Restore") { Task { await model.runRestore() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(restoreSummary)
        }
    }

    /// Destinations the restore will write, so nothing lands somewhere unexpected.
    private var restoreSummary: String {
        let chosen = model.chosenRestoreActions
        var lines = chosen.prefix(12).map { action in
            let note = action.destinationExists && !action.identical
                ? (model.restoreOverwrite ? " (replaces the existing file; it goes to the Trash)" : " (exists, skipped)")
                : ""
            return action.destinationURL.abbreviatingHome + note
        }
        if chosen.count > 12 { lines.append("…and \(chosen.count - 12) more") }
        return lines.joined(separator: "\n")
    }

    private func resultBar(_ result: RestoreResult) -> some View {
        Label("\(result.restored.count) restored · \(result.skipped.count) skipped · \(result.failed.count) failed",
              systemImage: result.failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(result.failed.isEmpty ? Color.green : Color.orange)
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(.quaternary.opacity(0.5))
    }
}

#Preview {
    VaultRestoreView().environment(AppModel()).frame(width: 860, height: 640)
}
