import SwiftUI

@main
struct CleanerApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        Settings {
            ContentUnavailableView("Settings", systemImage: "gearshape", description: Text("Coming soon."))
                .frame(width: 420, height: 300)
        }
    }
}
