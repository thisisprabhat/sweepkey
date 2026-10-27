import SweepkeyKit
import SwiftUI

struct VaultCollectView: View {
    @Environment(\.appModel) private var model
    @State private var showExport = false
    @State private var showAllWarnings = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VaultCollectOptionsView()
            Divider()
            if !model.vaultWarnings.isEmpty && !model.isFindingSecrets {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Some files need attention: repositories git could not query were collected by pattern only, and files over the size limit were skipped.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.medium))
                    // A long list would push the findings off screen: show a few, the rest on request.
                    let shown = showAllWarnings ? model.vaultWarnings : Array(model.vaultWarnings.prefix(3))
                    ForEach(shown, id: \.self) {
                        Text($0).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            .help($0)
                    }
                    if model.vaultWarnings.count > 3 {
                        Button(showAllWarnings ? "Show fewer" : "Show all \(model.vaultWarnings.count)") {
                            withAnimation(.smooth) { showAllWarnings.toggle() }
                        }
                        .buttonStyle(.link).font(.caption)
                    }
                }
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 8)
                Divider()
            }
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
        .task {
            guard AppRuntime.demoPresent == "vaultExport" else { return }
            await model.findSecrets()
            model.exportState = .idle
            showExport = true
        }
    }
}

#Preview {
    VaultCollectView().environment(\.appModel, AppModel()).frame(width: 860, height: 600)
}
