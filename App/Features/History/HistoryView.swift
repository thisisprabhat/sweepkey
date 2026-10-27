import SweepkeyKit
import SwiftUI

struct HistoryView: View {
    @Environment(\.appModel) private var model
    @State private var selectedID: UUID?

    private var cleanups: [CleanReport] { model.reports.filter { !$0.dryRun } }

    /// Reports grouped by month, newest month first, newest report first within a month.
    private var months: [(month: Date, reports: [CleanReport])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: model.reports) {
            calendar.date(from: calendar.dateComponents([.year, .month], from: $0.finishedAt)) ?? $0.finishedAt
        }
        return groups.map { ($0.key, $0.value.sorted { $0.finishedAt > $1.finishedAt }) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    StatTile(title: "Freed in total", value: SizeFormat.string(model.lifetimeFreedBytes),
                             symbolName: "checkmark.circle", tint: .green)
                    StatTile(title: "Cleanups", value: "\(cleanups.count)", symbolName: "clock.arrow.circlepath")
                    StatTile(title: "Last cleanup",
                             value: cleanups.first.map { $0.finishedAt.formatted(.relative(presentation: .named)) } ?? "Never",
                             symbolName: "calendar", tint: .primary)
                }
                .fixedSize(horizontal: false, vertical: true)
                if model.reports.isEmpty {
                    EmptyStateView("No history yet", symbolName: "clock.arrow.circlepath",
                                   message: "Every cleanup you run is recorded here, with what was removed and how much space it freed.")
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    let trend = model.cleanTrend
                    if trend.count > 1 {
                        SectionHeaderView("Freed over time", symbolName: "chart.bar.xaxis")
                        TrendChart(points: trend)
                    }
                    ForEach(months, id: \.month) { group in
                        SectionHeaderView(LocalizedStringKey(group.month.formatted(.dateTime.month(.wide).year())),
                                          symbolName: "calendar")
                        VStack(spacing: 8) {
                            ForEach(group.reports) { report in
                                HistoryCard(report: report, isSelected: selectedID == report.id) {
                                    selectedID = report.id
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("History")
        // A sheet, not an inspector: the inspector's split view re-measured this content's minimum
        // width on every layout pass and AppKit aborted with an update-constraints loop.
        .sheet(item: Binding(
            get: { model.reports.first { $0.id == selectedID } },
            set: { selectedID = $0?.id })) { report in
            VStack(spacing: 0) {
                HistoryDetailView(report: report)
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { selectedID = nil }.keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }
            .frame(width: 620, height: 520)
        }
        .task {
            await model.loadJournal()
            if AppRuntime.demoPresent == "historyDetail" { selectedID = model.reports.first?.id }
        }
    }
}

/// One cleanup as a clickable card; the details open in a sheet.
private struct HistoryCard: View {
    let report: CleanReport
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    private var cleanedCount: Int { report.items.filter { $0.status == .cleaned }.count }
    private var failedCount: Int { report.items.filter { $0.status == .failed }.count }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: report.dryRun ? "doc.text.magnifyingglass"
                      : report.mode == .trash ? "trash" : "flame")
                    .font(.title3)
                    .foregroundStyle(report.dryRun ? Color.secondary : Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(.tint.opacity(0.12), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(report.finishedAt, format: .dateTime.weekday(.wide).day().month().hour().minute())
                        .font(.callout.weight(.medium))
                    HStack(spacing: 6) {
                        Text("\(cleanedCount) of \(report.items.count) items")
                        Text("·")
                        Text(report.dryRun ? "Dry run" : report.mode == .trash ? "Moved to Trash" : "Deleted permanently")
                        if failedCount > 0 {
                            Text("·")
                            Text("\(failedCount) failed").foregroundStyle(.orange)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                SizeText(bytes: report.freedBytes)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(report.dryRun ? Color.secondary : Color.green)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(.rect)
            .background(.quaternary.opacity(hovering || isSelected ? 0.9 : 0.5), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: isSelected ? 1.5 : 0)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityHint("Shows what this cleanup removed")
    }
}

#Preview {
    HistoryView().environment(\.appModel, AppModel()).frame(width: 860, height: 560)
}
