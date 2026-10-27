import SweepkeyKit
import SwiftUI

struct DashboardView: View {
    @Environment(\.appModel) private var model
    @State private var disk = DiskInfo.current()
    @State private var hasFullDiskAccess = OnboardingAccessStep.hasAccess()

    var body: some View {
        ScrollView {
            if !hasFullDiskAccess && !AppRuntime.demoMode { fullDiskAccessBanner }
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
                if model.scanState.isScanning {
                    Button("Stop", systemImage: "stop.fill") { model.cancelScan() }
                        .buttonStyle(.glass)
                } else {
                    Button("Scan", systemImage: "magnifyingglass") { model.scan() }
                        .buttonStyle(.glassProminent)
                        .help("Scan for reclaimable space (⌘R)")
                }
            }
        }
        .onAppear { disk = DiskInfo.current(); hasFullDiskAccess = OnboardingAccessStep.hasAccess() }
        .onChange(of: model.diskRefreshToken) { _, _ in disk = DiskInfo.current() }
    }

    private var fullDiskAccessBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.trianglebadge.exclamationmark").foregroundStyle(.orange)
            Text("Sweepkey doesn't have Full Disk Access, so some caches and folders may be missed.")
                .font(.callout)
            Spacer()
            Button("Grant Access…") {
                model.onboardingStartStep = 2
                model.settings.hasCompletedOnboarding = false
            }
            .buttonStyle(.glass)
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 10))
        .padding([.horizontal, .top], 20)
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
            HStack(spacing: 14) {
                DiskUsageCard(disk: disk)
                StatTile(title: "Reclaimable", value: SizeFormat.string(model.reclaimableBytes),
                         symbolName: "arrow.3.trianglepath",
                         detail: "\(model.projects.filter { $0.reclaimableBytes > 0 }.count) projects and \(model.cacheGroups.count) cache groups")
                StatTile(title: "Freed so far", value: SizeFormat.string(model.lifetimeFreedBytes),
                         symbolName: "checkmark.circle", tint: .green, detail: "Across all cleanups")
            }
            .fixedSize(horizontal: false, vertical: true)
            SectionHeaderView("By category", symbolName: "chart.pie")
            if model.breakdown.isEmpty {
                Text("Nothing to reclaim.").foregroundStyle(.secondary)
            } else {
                CategoryDonut(slices: model.breakdown)
            }
            SectionHeaderView("Top offenders", symbolName: "chart.bar")
            TopOffendersList(candidates: model.topOffenders)
            InsightsSection()
        }
        .padding(20)
    }
}

#Preview {
    DashboardView().environment(\.appModel, AppModel()).frame(width: 800, height: 700)
}
