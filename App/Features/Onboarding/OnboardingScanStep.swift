import SwiftUI

struct OnboardingScanStep: View {
    @Environment(\.appModel) private var model

    var body: some View {
        VStack(spacing: 16) {
            switch model.scanState {
            case .idle:
                Image(systemName: "sparkle.magnifyingglass").font(.system(size: 56)).foregroundStyle(.tint)
                Text("Ready for your first scan").font(.title.weight(.semibold))
                Button("Start Scan", systemImage: "magnifyingglass") { model.scan() }
                    .buttonStyle(.glassProminent)
            case .scanning(let progress):
                ScanProgressRing()
                Text("Scanning… \(progress.projectsFound) projects").monospacedDigit()
            case .done(let summary):
                Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
                Text("\(SizeFormat.string(summary.totalBytes)) can be reclaimed").font(.title.weight(.semibold))
                Text("across \(summary.projectCount) projects").foregroundStyle(.secondary)
            }
        }
    }
}

#Preview { OnboardingScanStep().environment(\.appModel, AppModel()).padding().frame(width: 520, height: 400) }
