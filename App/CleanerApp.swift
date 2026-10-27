import SwiftUI

@main
struct CleanerApp: App {
    @State private var model = AppModel()
    @StateObject private var updater = UpdaterController()

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
        .commands {
            AppCommands(model: model)
            CommandGroup(after: .appInfo) { CheckForUpdatesView(updater: updater) }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// True while a screen that supports cleaning (Projects or Caches) is showing.
struct CleanScreenActiveKey: FocusedValueKey { typealias Value = Bool }

extension FocusedValues {
    var cleanScreenActive: Bool? {
        get { self[CleanScreenActiveKey.self] }
        set { self[CleanScreenActiveKey.self] = newValue }
    }
}

struct AppCommands: Commands {
    let model: AppModel
    @FocusedValue(\.cleanScreenActive) private var cleanScreenActive

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Scan") { model.scan() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.scanState.isScanning)
            Button("Clean Selection…") { model.requestClean() }
                // ⌘⌥⌫ rather than ⌘⌫: plain ⌘⌫ is "delete to line start" in text fields
                // and focus scoping cannot detect an active text field.
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .disabled(model.selection.isEmpty || cleanScreenActive != true)
        }
        CommandGroup(after: .toolbar) {
            Button("Toggle Inspector") { model.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: .command)
        }
    }
}
