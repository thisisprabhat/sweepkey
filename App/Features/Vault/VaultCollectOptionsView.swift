import SweepkeyKit
import SwiftUI

/// Session overrides for the Vault screen. Every control shows the settings value until changed;
/// changes apply to this session only and never replace the settings.
struct VaultCollectOptionsView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        DisclosureGroup("Collect options") {
            // Capped and scrollable so the findings below keep their room when this is open.
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                URLListEditor(title: "Roots", panelMessage: "Choose folders to search for secrets",
                              urls: override(\.roots, default: model.settings.scanRoots))
                Toggle("Include uncommitted work", isOn: override(
                    \.includeUncommittedWork, default: model.settings.vault.includeUncommittedWork))
                Toggle("Scan file contents for keys", isOn: override(
                    \.scanContents, default: model.settings.vault.scanContents))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Always collect").font(.headline)
                    StringListEditor(prompt: "File name, e.g. pubspec.yaml", items: override(
                        \.alwaysCollect, default: model.settings.vault.alwaysCollect))
                }
                if !model.vaultOverrides.isEmpty {
                    HStack {
                        Text("These changes apply to this session only.").font(.caption).foregroundStyle(.secondary)
                        Button("Use Settings") { model.vaultOverrides = VaultCollectOverrides() }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.trailing, 12)
            }
            .frame(maxHeight: 280)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    /// Reads the override, falling back to the settings value; writing stores an override.
    private func override<T: Equatable>(_ key: WritableKeyPath<VaultCollectOverrides, T?>, default value: T) -> Binding<T> {
        Binding(
            get: { model.vaultOverrides[keyPath: key] ?? value },
            set: { model.vaultOverrides[keyPath: key] = $0 == value ? nil : $0 })
    }
}

#Preview {
    VaultCollectOptionsView().environment(\.appModel, AppModel()).frame(width: 640)
}
