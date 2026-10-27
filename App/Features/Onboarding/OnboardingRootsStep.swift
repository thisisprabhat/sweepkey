import SwiftUI

struct OnboardingRootsStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            Text("Where are your projects?").font(.title.weight(.semibold))
            Text("Cleaner scans these folders for projects.").foregroundStyle(.secondary)
            URLListEditor(title: "Scan roots", panelMessage: "Choose folders that contain your projects",
                          urls: $model.settings.scanRoots)
            Button("Suggest Common Folders") {
                let home = FileManager.default.homeDirectoryForCurrentUser
                for name in ["Projects", "Developer", "Code", "src", "dev"] {
                    let url = home.appendingPathComponent(name, isDirectory: true)
                    if FileManager.default.fileExists(atPath: url.path), !model.settings.scanRoots.contains(url) {
                        model.settings.scanRoots.append(url)
                    }
                }
            }
            Spacer()
        }
    }
}

#Preview { OnboardingRootsStep().environment(AppModel()).padding().frame(width: 520, height: 400) }
