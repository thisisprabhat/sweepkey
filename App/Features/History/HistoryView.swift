import CleanerKit
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                StatTile(title: "Freed in total", value: SizeFormat.string(model.lifetimeFreedBytes),
                         symbolName: "checkmark.circle", tint: .green)
                StatTile(title: "Cleanups", value: "\(model.reports.filter { !$0.dryRun }.count)",
                         symbolName: "clock.arrow.circlepath")
            }
            .padding(16)
            if model.reports.isEmpty {
                EmptyStateView("No history yet", symbolName: "clock.arrow.circlepath",
                               message: "Cleanups you run will be listed here.")
            } else {
                HSplitView {
                    List(model.reports, selection: $selectedID) { report in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(report.finishedAt, format: .dateTime.day().month().year().hour().minute())
                                Text("\(report.items.count) items · \(report.mode == .trash ? "Trash" : "Permanent")\(report.dryRun ? " · Dry run" : "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            SizeText(bytes: report.freedBytes)
                        }
                        .tag(report.id)
                    }
                    .frame(minWidth: 280, idealWidth: 340)
                    Group {
                        if let report = model.reports.first(where: { $0.id == selectedID }) {
                            HistoryDetailView(report: report)
                        } else {
                            EmptyStateView("Select a cleanup", symbolName: "list.bullet.rectangle")
                        }
                    }
                    .frame(minWidth: 320)
                }
            }
        }
        .navigationTitle("History")
        .task { await model.loadJournal() }
    }
}

#Preview {
    HistoryView().environment(AppModel()).frame(width: 860, height: 560)
}
