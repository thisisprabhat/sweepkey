import AppKit
import Foundation

/// Thin wrappers over NSOpenPanel / NSSavePanel and Finder helpers.
@MainActor
enum Panels {
    static func chooseFolders(message: String, allowsMultiple: Bool = true) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = allowsMultiple
        panel.message = message
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseVault() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a vault folder, .zip or .dmg"
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func saveLocation(name: String, message: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.message = message
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openInTerminal(_ url: URL) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
