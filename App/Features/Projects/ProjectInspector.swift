import SweepkeyKit
import SwiftUI

struct ProjectInspector: View {
    @Environment(\.appModel) private var model

    private var candidate: Candidate? {
        guard let id = model.inspectedID else { return nil }
        return model.allCandidates.first { $0.id == id }
    }

    private var project: Project? {
        if let id = model.inspectedID, let match = model.projects.first(where: { $0.id == id }) { return match }
        return candidate.flatMap { model.project(containing: $0.id) }
    }

    var body: some View {
        if candidate == nil && project == nil {
            EmptyStateView("No selection", symbolName: "sidebar.trailing",
                           message: "Select a project or artifact to see its details.")
        } else {
            Form {
                if let candidate { candidateSection(candidate) }
                if let project { projectSection(project) }
            }
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom) {
                if let project { projectActions(project) }
            }
            .task(id: model.inspectedID) {
                if let candidate { await model.evaluateVerdicts(for: [candidate]) }
            }
        }
    }

    /// The two things you do with a project: clean all of it, or refresh it after changes.
    private func projectActions(_ project: Project) -> some View {
        HStack {
            Button("Rescan", systemImage: "arrow.clockwise") { model.rescanProject(project) }
                .buttonStyle(.glass)
                .disabled(model.scanState.isScanning || model.rescanningProjects.contains(project.id))
            Spacer()
            Button("Clean Project…", systemImage: "sparkles") { model.cleanProject(project) }
                .buttonStyle(.glassProminent)
                .disabled(project.candidates.isEmpty)
                .help("Select all of \(project.name)'s rebuildable folders and review them before cleaning")
        }
        .padding(12)
        .background(.bar)
    }

    @ViewBuilder private func candidateSection(_ candidate: Candidate) -> some View {
        Section("Artifact") {
            LabeledContent("Name", value: candidate.title)
            LabeledContent("Path") {
                Text(candidate.url.abbreviatingHome).textSelection(.enabled).multilineTextAlignment(.trailing)
            }
            LabeledContent("Rule", value: candidate.ruleID)
            LabeledContent("Size") { SizeText(bytes: candidate.sizeBytes) }
            LabeledContent("Risk") { RiskBadge(risk: candidate.risk) }
            if let hint = candidate.regenerateHint {
                LabeledContent("Regenerate") {
                    HStack {
                        Text(hint).font(.callout.monospaced()).textSelection(.enabled)
                        Button("Copy", systemImage: "doc.on.doc") { Panels.copy(hint) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
            }
            if let verdict = model.verdicts[candidate.id] { VerdictRow(verdict: verdict) }
            Button("Reveal in Finder", systemImage: "folder") { Panels.reveal(candidate.url) }
        }
    }

    @ViewBuilder private func projectSection(_ project: Project) -> some View {
        Section("Project") {
            LabeledContent("Name", value: project.name)
            LabeledContent("Path") {
                Text(project.url.abbreviatingHome).textSelection(.enabled).multilineTextAlignment(.trailing)
            }
            LabeledContent("Reclaimable") { SizeText(bytes: project.reclaimableBytes) }
            if let date = project.lastActivity {
                LabeledContent("Last activity") { Text(date, format: .relative(presentation: .named)) }
            }
        }
        if let git = project.git {
            Section("Git") {
                if let branch = git.branch { LabeledContent("Branch", value: branch) }
                if let remote = git.remoteURL {
                    LabeledContent("Remote") { Text(remote).font(.callout).textSelection(.enabled) }
                }
                if git.isDirty {
                    Label("Uncommitted changes", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                if let unpushed = git.unpushedCommitCount, unpushed > 0 {
                    Label("\(unpushed) unpushed commits", systemImage: "arrow.up.circle.fill").foregroundStyle(.orange)
                } else if git.unpushedCommitCount == nil {
                    Label("No upstream branch", systemImage: "questionmark.circle").foregroundStyle(.secondary)
                }
                if git.stashCount > 0 {
                    Label("\(git.stashCount) stashes", systemImage: "tray.full.fill").foregroundStyle(.orange)
                }
            }
        } else {
            Section("Git") { Text("Not a git repository").foregroundStyle(.secondary) }
        }
    }
}

struct VerdictRow: View {
    let verdict: SafetyVerdict

    var body: some View {
        switch verdict {
        case .allowed:
            Label("Safe to clean", systemImage: "checkmark.shield").foregroundStyle(.green)
        case .warning(let text):
            Label(text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .blocked(let text):
            Label(text, systemImage: "hand.raised.fill").foregroundStyle(.red)
        }
    }
}

#Preview {
    let model = AppModel()
    ProjectInspector().environment(\.appModel, model).frame(width: 320, height: 600)
}
