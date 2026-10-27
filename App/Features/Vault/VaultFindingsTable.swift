import CleanerKit
import SwiftUI

struct VaultFindingsTable: View {
    @Environment(AppModel.self) private var model
    @State private var previewID: String?

    private var rows: [FindingRow] { FindingRow.grouped(model.findings) }
    private var previewed: SecretFile? { model.findings.first { $0.id == previewID } }

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
                    HStack(spacing: 6) {
                        Image(systemName: row.file == nil ? "folder.fill" : "key.fill").foregroundStyle(.secondary)
                        Text(row.name).fontWeight(row.file == nil ? .medium : .regular)
                    }
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
    VaultFindingsTable().environment(model).frame(width: 760, height: 460)
        .task { await model.findSecrets() }
}
