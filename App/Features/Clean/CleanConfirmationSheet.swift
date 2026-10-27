import SweepkeyKit
import SwiftUI

struct CleanConfirmationSheet: View {
    @Environment(\.appModel) private var model
    @State private var acknowledged = false

    /// Danger items and items with a safety warning (e.g. the project is open) need acknowledgement.
    private func needsAcknowledgement(_ candidate: Candidate) -> Bool {
        AppLogic.needsAcknowledgement(candidate, verdict: model.verdicts[candidate.id])
    }

    private var needsAcknowledgementCount: Int { model.cleanableSelected.filter(needsAcknowledgement).count }
    private var total: Int64 { model.cleanableSelected.reduce(0) { $0 + $1.sizeBytes } }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            Text("Clean \(model.cleanableSelected.count) items?").font(.title2.weight(.semibold))
            List {
                Section {
                    ForEach(model.cleanableSelected) { candidate in
                        row(candidate, highlighted: needsAcknowledgement(candidate), dimmed: false)
                    }
                }
                if !model.blockedSelected.isEmpty {
                    Section("Blocked — will not be cleaned") {
                        ForEach(model.blockedSelected) { candidate in
                            row(candidate, highlighted: false, dimmed: true)
                        }
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 260)

            HStack {
                Text("Total").foregroundStyle(.secondary)
                SizeText(bytes: total).fontWeight(.semibold)
                Spacer()
                Picker("Delete mode", selection: $model.cleanMode) {
                    Text("Move to Trash").tag(DeleteMode.trash)
                    Text("Delete permanently").tag(DeleteMode.permanent)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            if model.cleanMode == .permanent {
                Label("Permanent deletion cannot be undone.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if needsAcknowledgementCount > 0 {
                Toggle("I understand the \(needsAcknowledgementCount) highlighted item(s) are high risk or belong to a project that looks open, and may contain files that cannot be regenerated.",
                       isOn: $acknowledged)
                    .toggleStyle(.checkbox)
            }
            HStack {
                Button("Cancel", role: .cancel) { model.dismissClean() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Dry Run") { model.startClean(dryRun: true, acknowledged: []) }
                    .buttonStyle(.glass)
                    .disabled(model.cleanableSelected.isEmpty)
                Button("Clean", systemImage: "trash") {
                    let shown = Set(model.cleanableSelected.filter(needsAcknowledgement).map(\.id))
                    model.startClean(dryRun: false, acknowledged: acknowledged ? shown : [])
                }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.cleanableSelected.isEmpty || (needsAcknowledgementCount > 0 && !acknowledged))
            }
        }
        .padding(20)
    }

    private func row(_ candidate: Candidate, highlighted: Bool, dimmed: Bool) -> some View {
        HStack(spacing: 8) {
            EcosystemIcon(ecosystemID: candidate.ecosystemID, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.title)
                Text(candidate.url.abbreviatingHome).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if !dimmed, case .warning? = model.verdicts[candidate.id], let verdict = model.verdicts[candidate.id] {
                    VerdictRow(verdict: verdict).font(.caption)
                }
                if dimmed {
                    if let verdict = model.verdicts[candidate.id] {
                        VerdictRow(verdict: verdict).font(.caption)
                    } else {
                        Label("Not yet checked", systemImage: "questionmark.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            RiskBadge(risk: candidate.risk)
            SizeText(bytes: candidate.sizeBytes)
        }
        .opacity(dimmed ? 0.5 : 1)
        .padding(.vertical, 2)
        .listRowBackground(highlighted ? Color.red.opacity(0.12) : nil)
    }
}

#Preview {
    let model = AppModel()
    CleanConfirmationSheet().environment(\.appModel, model).frame(width: 560)
        .task {
            model.projects = MockData.projects
            model.selection = Set(MockData.projects.prefix(4).flatMap(\.candidates).map(\.id))
            await model.beginClean()
        }
}
