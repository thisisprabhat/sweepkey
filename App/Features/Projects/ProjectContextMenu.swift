import SwiftUI

struct ProjectContextMenu: View {
    @Environment(AppModel.self) private var model
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
                Button("Copy Path", systemImage: "doc.on.doc") { Panels.copy(url.path) }
            }
            if let project {
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
