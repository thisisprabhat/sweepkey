import SweepkeyKit
import SwiftUI

struct RestoreActionsTable: View {
    @Environment(\.appModel) private var model

    var body: some View {
        Table(model.restoreActions) {
            TableColumn("") { action in
                Toggle("Restore \(action.entry.vaultPath)", isOn: Binding(
                    get: { model.restoreSelection.contains(action.id) },
                    set: { on in
                        if on { model.restoreSelection.insert(action.id) } else { model.restoreSelection.remove(action.id) }
                    })).labelsHidden()
            }
            .width(28)
            TableColumn("File") { action in Text(action.entry.vaultPath).lineLimit(1).truncationMode(.middle) }
            TableColumn("Destination") { action in
                Text(action.destinationURL.abbreviatingHome).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            TableColumn("Status") { action in
                if action.identical {
                    badge("Identical", .secondary)
                } else if action.destinationExists {
                    badge(model.restoreOverwrite ? "Will overwrite" : "Conflict", .orange)
                } else {
                    badge("New", .green)
                }
            }
            .width(110)
        }
    }

    private func badge(_ title: LocalizedStringKey, _ tint: Color) -> some View {
        Text(title).font(.caption.weight(.medium)).foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: .capsule)
    }
}
