import Foundation
import Observation

/// Observable automation flags that the UI can show. Kept apart from `AppModel` so Task 7's
/// model stays untouched.
@Observable @MainActor
final class AutomationState {
    static let shared = AutomationState()

    /// File changes were seen under the scan roots since the last scan.
    var resultsMayBeOutdated = false
    /// A quick clean, auto-clean or intent clean is in flight.
    var isCleaning = false
    /// One-line outcome of the last automation action (menu bar popover).
    var lastActionMessage: String?
    /// Set by the DEBUG-only launch argument path; true once the app was launched as a login item.
    var launchedAtLogin = false

    private init() {}
}
