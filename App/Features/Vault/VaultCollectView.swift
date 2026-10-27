import CleanerKit
import SwiftUI

struct VaultCollectView: View {
    @Environment(AppModel.self) private var model
    @State private var showExport = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VaultCollectOptionsView()
            Divider()
            if model.isFindingSecrets {
                VStack(spacing: 12) {
                    ScanProgressRing(symbolName: "lock.shield")
                    Text("Looking for secrets…")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.hasSearchedSecrets {
                EmptyStateView("Collect un-committed secrets", symbolName: "lock.shield",
                               message: "Find .env files, keystores and other files that aren't in git, then export them to a vault.") {
                    Button("Find Secrets", systemImage: "magnifyingglass") { Task { await model.findSecrets() } }
                        .buttonStyle(.glassProminent)
                }
            } else if model.findings.isEmpty {
                EmptyStateView("Nothing found", symbolName: "checkmark.shield",
                               message: "No un-committed secret files turned up in your roots.")
            } else {
                VaultFindingsTable()
            }
        }
        .toolbar {
            ToolbarItem {
                Button("Find Secrets", systemImage: "magnifyingglass") { Task { await model.findSecrets() } }
                    .disabled(model.isFindingSecrets)
            }
            ToolbarItem {
                Button("Export…", systemImage: "square.and.arrow.up") {
                    model.exportState = .idle
                    showExport = true
                }
                .buttonStyle(.glassProminent)
                .disabled(model.findingsSelection.isEmpty)
            }
        }
        .sheet(isPresented: $showExport) {
            VaultExportSheet()
        }
    }
}

#Preview {
    VaultCollectView().environment(AppModel()).frame(width: 860, height: 600)
}
