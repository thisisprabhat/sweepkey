import Foundation

extension AppModel {
    /// DEBUG screenshot helper for the landing page: with `-SweepkeyDemo YES`, opens the screen
    /// named by `-SweepkeyDemoPresent` once the demo scan has finished. Only the mock services run
    /// in demo mode, so a "clean" here never touches real files.
    func presentDemoScreen() async {
        guard let what = AppRuntime.demoPresent else { return }
        for _ in 0..<100 where scanState.isScanning || projects.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        switch what {
        case "inspector":
            inspectedID = projects.first?.id
            showInspector = true
        case "cleanConfirm", "cleanResult":
            selection = Set(projects.prefix(3).flatMap(\.candidates).map(\.id))
            await beginClean()
            if what == "cleanResult" {
                try? await Task.sleep(for: .milliseconds(600))
                startClean(dryRun: false, acknowledged: selection)
            }
        case "findSecrets":
            await findSecrets()
        default:
            break // historyDetail, ruleEditor, vaultExport are opened by their own screens
        }
    }
}
