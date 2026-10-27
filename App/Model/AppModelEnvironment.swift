import SwiftUI

/// The app model as an environment value that falls back to `AppModel.shared`.
///
/// `@Environment(AppModel.self)` traps when a view is hosted where the value was never injected,
/// and AppKit hosts some SwiftUI (toolbar items, inspectors, menus) in views of its own. There is
/// one model per app, so falling back to it is always correct and turns that crash into a no-op.
private struct AppModelKey: EnvironmentKey {
    static var defaultValue: AppModel { MainActor.assumeIsolated { AppModel.shared } }
}

extension EnvironmentValues {
    var appModel: AppModel {
        get { self[AppModelKey.self] }
        set { self[AppModelKey.self] = newValue }
    }
}
