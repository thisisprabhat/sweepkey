import SwiftUI

@main
struct CleanerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if model.settings.hasCompletedOnboarding {
                    RootView()
                } else {
                    OnboardingView()
                }
            }
            .environment(model)
        }
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Scan") { model.scan() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.scanState.isScanning)
            Button("Clean Selection…") { model.requestClean() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selection.isEmpty)
        }
        CommandGroup(after: .toolbar) {
            Button("Toggle Inspector") { model.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: .command)
        }
    }
}
