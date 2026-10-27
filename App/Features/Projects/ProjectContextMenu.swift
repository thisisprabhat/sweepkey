import SwiftUI

struct ProjectContextMenu: View {
    @Environment(\.appModel) private var model
    let ids: Set<String>

    var body: some View {
        if let id = ids.first {
            let candidate = model.allCandidates.first { $0.id == id }
            let project = model.projects.first { $0.id == id } ?? candidate.flatMap { model.project(containing: $0.id) }
            if let url = candidate?.url ?? project?.url {
                Button("Reveal in Finder", systemImage: "folder") { Panels.reveal(url) }
                Button("Open in Terminal", systemImage: "terminal") {
                    Panels.openInTerminal(project?.url ?? url.deletingLastPathComponent())
                }
                Button("Open in Editor", systemImage: "chevron.left.forwardslash.chevron.right") {
                    Editor.open(project?.url ?? url.deletingLastPathComponent())
                }
                Button("Copy Path", systemImage: "doc.on.doc") { Panels.copy(url.path) }
            }
            if let project {
                Divider()
                Button("Clean This Project…", systemImage: "sparkles") { model.cleanProject(project) }
                    .disabled(project.candidates.isEmpty)
                Button("Rescan This Project", systemImage: "arrow.clockwise") { model.rescanProject(project) }
                    .disabled(model.scanState.isScanning || model.rescanningProjects.contains(project.id))
                Divider()
                Button(model.isPinned(project) ? "Unpin Project" : "Pin Project",
                       systemImage: model.isPinned(project) ? "pin.slash" : "pin") {
                    model.togglePin(project)
                }
                Button("Exclude Project", systemImage: "eye.slash") { model.exclude(project) }
            }
        }
    }
}
