import SweepkeyKit
import SwiftUI

private enum TreemapMode: String, CaseIterable, Identifiable {
    case project = "By project", ecosystem = "By ecosystem"
    var id: String { rawValue }
}

/// Insight cards, the reclaimable-space treemap and the cleaning trend; shown on the Dashboard.
struct InsightsSection: View {
    @Environment(\.appModel) private var model
    @State private var mode = TreemapMode.project

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            let insights = model.insights
            if !insights.isEmpty {
                SectionHeaderView("Insights", symbolName: "lightbulb")
                ForEach(insights) { insight in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: insight.symbolName)
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.title).font(.callout.weight(.medium))
                            Text(insight.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if insight.estimatedBytes > 0 {
                            SizeText(bytes: insight.estimatedBytes).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                    .accessibilityElement(children: .combine)
                }
            }

            let items = mode == .project ? model.treemapByProject : model.treemapByEcosystem
            SectionHeaderView(title: "Where the space is", symbolName: "square.grid.2x2") {
                Picker("Grouping", selection: $mode) {
                    ForEach(TreemapMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            if items.isEmpty {
                Text("Nothing to show.").foregroundStyle(.secondary)
            } else {
                // Project tiles get the same right-click actions as the Projects list.
                TreemapView(items: items, menu: mode == .project
                    ? { AnyView(ProjectContextMenu(ids: [$0.id]).environment(\.appModel, model)) } : nil)
            }

            let trend = model.cleanTrend
            if !trend.isEmpty {
                SectionHeaderView("Freed over time", symbolName: "chart.bar.xaxis")
                TrendChart(points: trend)
            }
        }
    }
}

#Preview {
    InsightsSection().environment(\.appModel, AppModel()).padding().frame(width: 700)
}
