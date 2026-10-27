import SweepkeyKit
import SwiftUI

struct VaultFindingsTable: View {
    @Environment(\.appModel) private var model
    @State private var previewID: String?

    private var rows: [FindingRow] { FindingRow.grouped(model.findings) }
    private var previewed: SecretFile? { model.findings.first { $0.id == previewID } }

    private func ecosystem(of row: FindingRow) -> String? {
        guard let root = row.files.first?.git?.repositoryRoot.standardizedFileURL else { return nil }
        let project = model.projects.first { $0.url.standardizedFileURL == root }
            ?? model.projects.first { $0.url.standardizedFileURL.path.hasPrefix(root.path + "/") }
        return project?.ecosystemIDs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(rows, children: \.children, selection: $previewID) {
                TableColumn("") { row in
                    Toggle("Select \(row.name)", isOn: Binding(
                        get: { row.files.allSatisfy { model.findingsSelection.contains($0.id) } },
                        set: { on in
                            if on { model.findingsSelection.formUnion(row.files.map(\.id)) }
                            else { model.findingsSelection.subtract(row.files.map(\.id)) }
                        })).labelsHidden()
                }
                .width(28)
                TableColumn("File") { row in
                    HStack(spacing: 8) {
                        if let file = row.file {
                            LogoIcon(logo: file.icon.logo, symbolName: file.icon.symbol, size: 20)
                        } else {
                            // The project's framework logo, from the last scan; a folder when unknown.
                            LogoIcon(logo: ecosystem(of: row), symbolName: "folder.fill", size: 22)
                        }
                        Text(row.name).fontWeight(row.file == nil ? .medium : .regular)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .help(row.file?.sourceURL.abbreviatingHome ?? row.name)
                }
                TableColumn("Reason") { row in
                    if let reason = row.file?.reason {
                        Text(reason.title)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: .capsule)
                    }
                }
                TableColumn("Size") { row in SizeText(bytes: row.sizeBytes) }
                    .width(80)
            }
            if let previewed { MaskedPreviewView(file: previewed) }
            HStack {
                Text("\(model.findingsSelection.count) of \(model.findings.count) selected")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)
        }
    }
}

#Preview {
    let model = AppModel()
    VaultFindingsTable().environment(\.appModel, model).frame(width: 760, height: 460)
        .task { await model.findSecrets() }
}
