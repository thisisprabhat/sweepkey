import CleanerKit
import SwiftUI

struct CleanResultView: View {
    @Environment(AppModel.self) private var model
    let report: CleanReport

    private var failures: [CleanItemResult] { report.items.filter { $0.status == .failed } }

    private var approximate: [CleanItemResult] { report.items.filter(AppLogic.isApproximate) }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: report.dryRun ? "doc.text.magnifyingglass" : "checkmark.seal.fill")
                .font(.system(size: 54))
                .foregroundStyle(report.dryRun ? Color.secondary : Color.green)
                .symbolEffect(.bounce, options: .nonRepeating, value: report.id)
            if report.dryRun {
                Text("Dry run complete").font(.title2.weight(.semibold))
                Text("\(SizeFormat.string(report.items.reduce(0) { $0 + $1.freedBytes })) would be freed. Nothing was deleted.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(SizeFormat.string(report.freedBytes)) freed").font(.title.weight(.semibold)).monospacedDigit()
                Text(report.mode == .trash ? "Items were moved to the Trash." : "Items were deleted permanently.")
                    .foregroundStyle(.secondary)
            }
            if !approximate.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(approximate, id: \.candidate.id) { item in
                        Text("\(item.candidate.title): up to \(SizeFormat.string(item.candidate.sizeBytes)) (exact size not measurable)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !failures.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(failures.count) failed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    ForEach(failures, id: \.candidate.id) { item in
                        Text("\(item.candidate.title): \(item.message ?? "Unknown error")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            }
            Spacer(minLength: 0)
            Button("Done") { model.dismissClean() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

#Preview {
    let items = MockData.projects[0].candidates.map { CleanItemResult(candidate: $0, status: .cleaned, freedBytes: $0.sizeBytes) }
    CleanResultView(report: CleanReport(startedAt: .now, finishedAt: .now, mode: .trash, dryRun: false, items: items))
        .environment(AppModel()).frame(width: 560)
}
