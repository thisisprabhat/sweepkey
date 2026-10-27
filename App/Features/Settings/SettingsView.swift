import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettingsTab() }
            Tab("Vault", systemImage: "lock.shield") { VaultSettingsTab() }
            Tab("Automation", systemImage: "clock.badge.checkmark") { AutomationSettingsTab() }
            Tab("Rules", systemImage: "list.bullet.rectangle") { RulesView() }
        }
        .frame(width: 600, height: 460)
    }
}

#Preview {
    SettingsView().environment(\.appModel, AppModel())
}
