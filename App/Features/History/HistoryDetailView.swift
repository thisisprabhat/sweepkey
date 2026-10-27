import SweepkeyKit
import SwiftUI

struct HistoryDetailView: View {
    @Environment(\.appModel) private var model
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
                        .disabled(model.putBackDone.contains(report.id) || model.puttingBack.contains(report.id))
                }
            }
            if let state = model.putBackState[report.id] {
                Text(state).font(.callout).foregroundStyle(.secondary)
            }
            List(report.items, id: \.candidate.id) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.candidate.title).lineLimit(1).truncationMode(.middle)
                        Text(item.candidate.url.abbreviatingHome).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .help(item.candidate.title)
                    Spacer(minLength: 8)
                    Text(item.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                    if AppLogic.isApproximate(item) {
                        Text("Not measured").font(.caption).foregroundStyle(.secondary)
                            .help("This item was removed by a tool, so its exact size could not be measured")
                    } else {
                        SizeText(bytes: item.freedBytes)
                    }
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
    .environment(\.appModel, model).frame(width: 480, height: 400)
}
