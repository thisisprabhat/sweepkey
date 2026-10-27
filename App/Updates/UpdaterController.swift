import Foundation
import Sparkle
import SwiftUI

/// Wraps Sparkle's standard updater. The updater only starts when the app was built with a
/// non-empty `SUPublicEDKey` (build setting `SPARKLE_PUBLIC_KEY`); otherwise update checks are
/// disabled so that unsigned local builds never talk to the network.
@MainActor
final class UpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController?

    /// True when an EdDSA public key is configured and the updater is running.
    let isEnabled: Bool

    @Published private(set) var canCheckForUpdates = false

    init(bundle: Bundle = .main) {
        let key = (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if key.isEmpty {
            controller = nil
            isEnabled = false
        } else {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            self.controller = controller
            isEnabled = true
            controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        }
    }

    func checkForUpdates() {
        guard isEnabled else { return }
        controller?.checkForUpdates(nil)
    }
}

/// The "Check for Updates…" menu item.
struct CheckForUpdatesView: View {
    @ObservedObject var updater: UpdaterController

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.isEnabled || !updater.canCheckForUpdates)
    }
}
