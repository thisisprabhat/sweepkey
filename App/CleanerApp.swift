import AppKit
import SwiftUI

/// Receives folders dropped on the Dock icon or opened with the app.
final class CleanerAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var onOpen: (([URL]) -> Void)?
    private var pending: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AutomationController.shared.start() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            if let handler = Self.onOpen { handler(urls) } else { pending += urls }
        }
    }

    @MainActor func flushPending() {
        guard !pending.isEmpty else { return }
        Self.onOpen?(pending)
        pending = []
    }
}

@main
struct CleanerApp: App {
    @NSApplicationDelegateAdaptor(CleanerAppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if model.settings.hasCompletedOnboarding {
                    RootView()
                } else {
                    OnboardingView(startStep: model.onboardingStartStep)
                }
            }
            .environment(model)
            .onAppear {
                CleanerAppDelegate.onOpen = { [model] urls in model.addScanRoots(urls) }
                delegate.flushPending()
            }
            .onOpenURL { AppRouter.handle($0, model: model) }
        }
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra(
            "Cleaner", systemImage: "externaldrive.badge.checkmark",
            isInserted: Binding(
                get: { model.settings.showMenuBarExtra }, set: { model.settings.showMenuBarExtra = $0 })
        ) {
            MenuBarPopover()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
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
