import CleanerKit
import SwiftUI

struct ArchiveRecipeView: View {
    @Environment(AppModel.self) private var model
    @State private var projectID: String?
    @State private var vaultDestination: URL?
    @State private var archiveDirectory: URL?
    @State private var zip = true
    @State private var acknowledge = false
    @State private var confirming = false
    @State private var running = false
    @State private var report: ArchiveReport?

    private var project: Project? { model.projects.first { $0.id == projectID } }
    private var risks: [ArchiveRisk] { project.map { PreArchiveCheck.risks(projects: [$0]) } ?? [] }
    private var canRun: Bool {
        project != nil && vaultDestination != nil && (!zip || archiveDirectory != nil)
            && (risks.isEmpty || acknowledge) && !running
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeaderView("Archive a project", symbolName: "archivebox")
            Text("Saves the project's secrets to a vault, deletes its build artifacts, then optionally zips it and moves the original to the Trash once the zip is verified.")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Project", selection: $projectID) {
                Text("Choose…").tag(String?.none)
                ForEach(model.projects) { Text($0.name).tag(Optional($0.id)) }
            }
            folderRow("Vault folder", url: vaultDestination) { vaultDestination = Panels.chooseFolders(message: "Choose a vault folder", allowsMultiple: false).first }
            Toggle("Zip the project and move the original to the Trash", isOn: $zip)
            if zip {
                folderRow("Archive folder", url: archiveDirectory) { archiveDirectory = Panels.chooseFolders(message: "Choose where to save the zip", allowsMultiple: false).first }
            }
            if !risks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(risks) { Label($0.message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    Toggle("I understand and want to continue anyway", isOn: $acknowledge)
                }
            }
            Button("Archive…", systemImage: "archivebox") { confirming = true }
                .buttonStyle(.glassProminent)
                .disabled(!canRun)
            if running { ProgressView("Archiving…") }
            if let report { reportView(report) }
        }
        .onChange(of: projectID) { _, _ in acknowledge = false; report = nil }
        .confirmationDialog(
            zip ? "Archive \(project?.name ?? "project")? Build artifacts are deleted permanently and the original moves to the Trash after the zip is verified."
                : "Archive \(project?.name ?? "project")? Build artifacts are deleted permanently.",
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Archive", role: .destructive) { run() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func folderRow(_ title: LocalizedStringKey, url: URL?, choose: @escaping () -> Void) -> some View {
        HStack {
            Text(title).frame(width: 110, alignment: .leading)
            Text(url?.abbreviatingHome ?? "Not chosen").foregroundStyle(url == nil ? .secondary : .primary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Choose…", action: choose)
        }
    }

    private func reportView(_ report: ArchiveReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(report.steps.enumerated()), id: \.offset) { _, step in
                HStack(alignment: .top) {
                    let needsAck = report.requiresAcknowledgement && step.status == .failed
                    Image(systemName: step.status == .done ? "checkmark.circle.fill"
                          : step.status == .skipped ? "minus.circle"
                          : needsAck ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(step.status == .done ? .green : step.status == .skipped ? .secondary
                                         : needsAck ? .orange : .red)
                    VStack(alignment: .leading) {
                        Text(step.name).font(.callout.weight(.medium))
                        if !step.detail.isEmpty { Text(step.detail).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if report.succeeded { Text("Done. Freed \(SizeFormat.string(report.freedBytes)).").font(.callout) }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }

    private func run() {
        guard let project, let vaultDestination else { return }
        running = true
        report = nil
        Task {
            report = await model.runArchive(
                project: project, vaultDestination: vaultDestination,
                archiveDirectory: zip ? archiveDirectory : nil, zip: zip, acknowledgeRisks: acknowledge)
            running = false
            if report?.trashedProject == true { projectID = nil }
        }
    }
}

#Preview {
    ArchiveRecipeView().environment(AppModel()).padding().frame(width: 700)
}
