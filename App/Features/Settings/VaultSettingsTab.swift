import CleanerKit
import SwiftUI

struct VaultSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                LabeledContent("Destination") {
                    HStack {
                        Text(model.settings.vault.destination?.abbreviatingHome ?? "Not set").foregroundStyle(.secondary)
                        Button("Choose…") {
                            if let url = Panels.chooseFolders(message: "Choose the vault folder", allowsMultiple: false).first {
                                model.settings.vault.destination = url
                            }
                        }
                    }
                }
                Picker("Default format", selection: $model.settings.vault.defaultFormat) {
                    Text("Folder").tag(VaultExportFormat.folder)
                    Text("Zip archive").tag(VaultExportFormat.zip)
                    Text("Encrypted image").tag(VaultExportFormat.encryptedImage)
                }
                Stepper("Keep \(model.settings.vault.keepVersions) versions",
                        value: $model.settings.vault.keepVersions, in: 1...50)
            }
            Section("Collect") {
                Toggle("Include uncommitted work", isOn: $model.settings.vault.includeUncommittedWork)
                Toggle("Scan file contents for keys", isOn: $model.settings.vault.scanContents)
                LabeledContent("Always collect") {
                    StringListEditor(prompt: "File name", items: $model.settings.vault.alwaysCollect)
                }
                LabeledContent("Extra patterns") {
                    StringListEditor(prompt: "Glob pattern", items: $model.settings.vault.extraPatterns)
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview { VaultSettingsTab().environment(AppModel()).frame(width: 600, height: 460) }
