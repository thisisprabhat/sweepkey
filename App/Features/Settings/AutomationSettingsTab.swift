import SwiftUI

struct AutomationSettingsTab: View {
    @Environment(\.appModel) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Schedule") {
                Toggle("Scan automatically", isOn: $model.settings.schedule.autoScanEnabled)
                if model.settings.schedule.autoScanEnabled {
                    Stepper("Every \(model.settings.schedule.autoScanIntervalHours) hours",
                            value: $model.settings.schedule.autoScanIntervalHours, in: 1...168)
                }
                Toggle("Clean stale projects automatically", isOn: $model.settings.schedule.autoCleanStaleEnabled)
                if model.settings.schedule.autoCleanStaleEnabled {
                    Stepper("Every \(model.settings.schedule.autoCleanIntervalDays) days",
                            value: $model.settings.schedule.autoCleanIntervalDays, in: 1...90)
                }
                Toggle("Snapshot the vault automatically", isOn: $model.settings.schedule.autoVaultSnapshotEnabled)
                if model.settings.schedule.autoVaultSnapshotEnabled {
                    Stepper("Every \(model.settings.schedule.autoVaultIntervalDays) days",
                            value: $model.settings.schedule.autoVaultIntervalDays, in: 1...90)
                }
            }
            Section("Alerts") {
                Toggle("Warn when disk space is low", isOn: $model.settings.lowSpaceAlertsEnabled)
                if model.settings.lowSpaceAlertsEnabled {
                    Stepper("Below \(model.settings.lowSpaceThresholdGB) GB free",
                            value: $model.settings.lowSpaceThresholdGB, in: 1...500, step: 5)
                }
            }
            Section("App") {
                Toggle("Show in menu bar", isOn: $model.settings.showMenuBarExtra)
                Toggle("Launch at login", isOn: $model.settings.launchAtLogin)
                    .onChange(of: model.settings.launchAtLogin) { _, enabled in
                        do {
                            try LoginItem.set(enabled: enabled)
                        } catch {
                            model.lastError = error.localizedDescription
                        }
                    }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview { AutomationSettingsTab().environment(\.appModel, AppModel()).frame(width: 600, height: 460) }
