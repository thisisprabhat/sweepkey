import CleanerKit
import SwiftUI

struct GeneralSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                URLListEditor(title: "Scan roots", panelMessage: "Choose folders to scan",
                              urls: $model.settings.scanRoots)
                URLListEditor(title: "Excluded folders", panelMessage: "Choose folders to skip",
                              urls: $model.settings.excludedPaths)
            }
            Section {
                Stepper("Stale after \(model.settings.staleAfterDays) days",
                        value: $model.settings.staleAfterDays, in: 7...730, step: 7)
                Picker("Delete mode", selection: $model.settings.defaultDeleteMode) {
                    Text("Move to Trash").tag(DeleteMode.trash)
                    Text("Delete permanently").tag(DeleteMode.permanent)
                }
                Toggle("Require a vault export before cleaning", isOn: $model.settings.requireVaultBeforeClean)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview { GeneralSettingsTab().environment(AppModel()).frame(width: 600, height: 460) }
