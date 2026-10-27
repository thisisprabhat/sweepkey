import AppKit
import Foundation

/// Finder integration.
@MainActor
enum Finder {
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// Terminal.app integration.
@MainActor
enum Terminal {
    static func open(_ url: URL) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Opens a folder in VS Code when it is installed (app bundle or `code` on a common path), else Finder.
@MainActor
enum Editor {
    static func open(_ url: URL) {
        if let code = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") {
            NSWorkspace.shared.open([url], withApplicationAt: code, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        let candidates = ["/usr/local/bin/code", "/opt/homebrew/bin/code"]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = [url.path]
            if (try? process.run()) != nil { return }
        }
        Finder.reveal(url)
    }
}
