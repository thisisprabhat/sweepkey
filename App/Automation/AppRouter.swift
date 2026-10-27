import AppKit
import SwiftUI

/// Entry points from outside the window: URL scheme, notification actions and the Services menu.
/// None of them deletes anything; `clean-safe` only opens the pre-filled confirmation sheet.
@MainActor
enum AppRouter {
    static func handle(_ url: URL, model: AppModel = .shared) {
        AutomationLog.info("open url \(url.absoluteString)")
        if url.isFileURL {
            model.addScanRoots([url])
            return
        }
        guard url.scheme == "cleaner" else { return }
        showApp()
        AutomationLog.info("handling URL \(url.absoluteString)")
        switch url.host {
        case "scan":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let paths = items.filter { $0.name == "path" }.compactMap(\.value).filter { !$0.isEmpty }
            if paths.isEmpty {
                model.scan()
            } else {
                model.requestPathScan(
                    paths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }, fromURL: true)
            }
        case "clean-safe":
            Task { await model.presentSafeCleanSheet() }
        default:
            AutomationLog.info("ignored URL \(url.absoluteString)")
        }
    }

    /// Brings the app forward as a regular app (leaving accessory mode).
    static func showApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens the window (creating it if needed) via the app's own URL scheme.
    static func openCleanSafe() {
        showApp()
        if let url = URL(string: "cleaner://clean-safe") { NSWorkspace.shared.open(url) }
    }
}

/// Services menu provider: "Scan with Cleaner" for folders selected in Finder.
final class ServicesProvider: NSObject {
    @objc func scanWithCleaner(
        _ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let urls = (pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else {
            error.pointee = "No folder was provided."
            return
        }
        Task { @MainActor in
            AppRouter.showApp()
            AppModel.shared.requestPathScan(urls, fromURL: false)
        }
    }
}
