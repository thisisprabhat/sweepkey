import SweepkeyKit
import SwiftUI

struct MigrationRecipeView: View {
    @Environment(\.appModel) private var model
    @State private var destination: URL?
    @State private var running = false
    @State private var result: MigrationResult?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeaderView("New-Mac migration", symbolName: "laptopcomputer.and.arrow.down")
            Text("Writes a bundle with a vault of your secrets, a list of every git repo (repos.json) and a restore.sh that clones them to the same relative paths. On the new Mac, run restore.sh, then restore the vault by git remote.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Text(destination?.abbreviatingHome ?? "No destination chosen")
                    .foregroundStyle(destination == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") {
                    destination = Panels.chooseFolders(message: "Choose where to write the migration bundle", allowsMultiple: false).first
                }
            }
            Button("Create bundle", systemImage: "shippingbox") { run() }
                .buttonStyle(.glassProminent)
                .disabled(destination == nil || running || model.settings.scanRoots.isEmpty)
            if running { ProgressView("Scanning repositories…") }
            if let errorMessage { Label(errorMessage, systemImage: "xmark.octagon.fill").foregroundStyle(.red) }
            if let result {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(result.repos.count) repositories listed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    if let vault = result.vault {
                        Text("\(vault.copiedCount + vault.unchangedCount) vault files saved")
                    } else {
                        Text("No secret files found for the vault.").foregroundStyle(.secondary)
                    }
                    Button("Show in Finder", systemImage: "folder") { Panels.reveal(result.directory) }
                }
            }
        }
    }

    private func run() {
        guard let destination else { return }
        running = true
        result = nil
        errorMessage = nil
        Task {
            do { result = try await model.exportMigration(to: destination.appendingPathComponent("Sweepkey Migration", isDirectory: true)) }
            catch { errorMessage = error.localizedDescription }
            running = false
        }
    }
}

#Preview {
    MigrationRecipeView().environment(\.appModel, AppModel()).padding().frame(width: 700)
}
