import CleanerKit
import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var disk = DiskInfo.current()

    var body: some View {
        ScrollView {
            switch model.scanState {
            case .idle:
                EmptyStateView("Ready to scan", symbolName: "sparkle.magnifyingglass",
                               message: "Find build artifacts and caches you can safely reclaim.") {
                    Button("Scan", systemImage: "magnifyingglass") { model.scan() }
                        .buttonStyle(.glassProminent)
                }
                .frame(minHeight: 360)
            case .scanning(let progress):
                scanning(progress)
            case .done:
                content
            }
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem {
                Button("Scan", systemImage: "magnifyingglass") { model.scan() }
                    .buttonStyle(.glassProminent)
                    .disabled(model.scanState.isScanning)
                    .help("Scan for reclaimable space (⌘R)")
            }
        }
        .onAppear { disk = DiskInfo.current() }
    }

    private func scanning(_ progress: ScanProgress) -> some View {
        VStack(spacing: 16) {
            ScanProgressRing()
            Text("Scanning…").font(.title3)
            Text("\(progress.projectsFound) projects · \(SizeFormat.string(progress.bytesFound))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(progress.currentPath)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            Grid(horizontalSpacing: 14) {
                GridRow {
                    DiskUsageCard(disk: disk)
                    StatTile(title: "Reclaimable", value: SizeFormat.string(model.reclaimableBytes),
                             symbolName: "arrow.3.trianglepath")
                    StatTile(title: "Freed so far", value: SizeFormat.string(model.lifetimeFreedBytes),
                             symbolName: "checkmark.circle", tint: .green)
                }
            }
            SectionHeaderView("By category", symbolName: "chart.pie")
            if model.breakdown.isEmpty {
                Text("Nothing to reclaim.").foregroundStyle(.secondary)
            } else {
                CategoryDonut(slices: model.breakdown)
            }
            SectionHeaderView("Top offenders", symbolName: "chart.bar")
            TopOffendersList(candidates: model.topOffenders)
        }
        .padding(20)
    }
}

#Preview {
    DashboardView().environment(AppModel()).frame(width: 800, height: 700)
}
