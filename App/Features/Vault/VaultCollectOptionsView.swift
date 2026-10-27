import SwiftUI

struct VaultCollectOptionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        DisclosureGroup("Collect options") {
            VStack(alignment: .leading, spacing: 12) {
                URLListEditor(title: "Roots", panelMessage: "Choose folders to search for secrets",
                              urls: $model.vaultOptions.roots)
                Toggle("Include uncommitted work", isOn: $model.vaultOptions.includeUncommittedWork)
                Toggle("Scan file contents for keys", isOn: $model.vaultOptions.scanContents)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Always collect").font(.headline)
                    StringListEditor(prompt: "File name, e.g. pubspec.yaml", items: $model.vaultOptions.alwaysCollect)
                }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

#Preview {
    VaultCollectOptionsView().environment(AppModel()).frame(width: 640)
}
