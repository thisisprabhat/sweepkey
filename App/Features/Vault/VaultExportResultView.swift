import SweepkeyKit
import SwiftUI

struct VaultExportResultView: View {
    let result: VaultExportResult
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill").font(.system(size: 44)).foregroundStyle(.green)
            Text("Vault exported").font(.title3.weight(.semibold))
            Text("\(result.copiedCount) copied · \(result.unchangedCount) unchanged")
                .foregroundStyle(.secondary).monospacedDigit()
            Text(result.outputURL.abbreviatingHome).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Reveal in Finder", systemImage: "folder") { Panels.reveal(result.outputURL) }
                    .buttonStyle(.glass)
                Button("Done", action: onDone).buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
