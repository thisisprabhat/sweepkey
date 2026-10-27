import CleanerKit
import SwiftUI

struct HistoryDetailView: View {
    @Environment(AppModel.self) private var model
    let report: CleanReport

    private var canPutBack: Bool {
        report.mode == .trash && !report.dryRun && report.items.contains { $0.status == .cleaned && $0.trashURL != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text(SizeFormat.string(report.freedBytes) + " freed").font(.title3.weight(.semibold))
                    Text(report.finishedAt, format: .dateTime.day().month().year().hour().minute())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if canPutBack {
                    Button("Put Back", systemImage: "arrow.uturn.backward") { Task { await model.putBack(report) } }
                        .buttonStyle(.glass)
                }
            }
            if let state = model.putBackState[report.id] {
                Text(state).font(.callout).foregroundStyle(.secondary)
            }
            List(report.items, id: \.candidate.id) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.candidate.title)
                        Text(item.candidate.url.abbreviatingHome).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Text(item.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                    SizeText(bytes: item.freedBytes)
                }
            }
        }
        .padding(16)
    }
}

#Preview {
    let model = AppModel()
    HistoryDetailView(report: CleanReport(
        startedAt: .now, finishedAt: .now, mode: .trash, dryRun: false,
        items: MockData.projects[0].candidates.map {
            CleanItemResult(candidate: $0, status: .cleaned, freedBytes: $0.sizeBytes, trashURL: URL(fileURLWithPath: "/tmp/x"))
        }))
    .environment(model).frame(width: 480, height: 400)
}
