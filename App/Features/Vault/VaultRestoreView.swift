import CleanerKit
import SwiftUI

struct VaultRestoreView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingEncrypted: URL?
    @State private var password = ""

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
            Button("Cancel", role: .cancel) { password = ""; pendingEncrypted = nil }
        } message: {
            Text("Enter the password for this encrypted image.")
        }
    }

    private func open() {
        guard let url = Panels.chooseVault() else { return }
        if url.pathExtension.lowercased() == "dmg" {
            pendingEncrypted = url
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
            RestoreActionsTable()
            if let result = model.restoreResult { resultBar(result) }
            HStack {
                Button("Close Vault") { Task { await model.closeVault() } }
                Spacer()
                Button("Restore \(model.restoreSelection.count) Files", systemImage: "arrow.uturn.backward") {
                    Task { await model.runRestore() }
                }
                .buttonStyle(.glassProminent)
                .disabled(model.restoreSelection.isEmpty || model.isRestoring)
            }
            .padding(12)
        }
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
