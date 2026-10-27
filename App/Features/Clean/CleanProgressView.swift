import CleanerKit
import SwiftUI

struct CleanProgressView: View {
    let progress: CleanProgress

    var body: some View {
        VStack(spacing: 16) {
            ScanProgressRing(fraction: progress.total > 0 ? Double(progress.completed) / Double(progress.total) : nil,
                             symbolName: "trash")
            Text("Cleaning…").font(.title3)
            Text("\(progress.completed) of \(progress.total)").monospacedDigit().foregroundStyle(.secondary)
            if !progress.currentTitle.isEmpty {
                Text(progress.currentTitle).font(.callout).foregroundStyle(.tertiary)
            }
            Text("\(SizeFormat.string(progress.freedBytes)) freed so far")
                .monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

#Preview {
    CleanProgressView(progress: CleanProgress(completed: 3, total: 8, currentTitle: "node_modules", freedBytes: 1_500_000_000))
        .frame(width: 560)
}
