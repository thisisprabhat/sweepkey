import CleanerKit
import SwiftUI

struct ProjectsView: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder = [KeyPathComparator(\ProjectRow.bytes, order: .reverse)]

    private var rows: [ProjectRow] {
        model.filteredProjects.map(ProjectRow.init(project:)).sorted(using: sortOrder)
    }

    var body: some View {
        @Bindable var model = model
        Group {
            if model.projects.isEmpty {
                EmptyStateView(model.scanState.isScanning ? "Scanning…" : "No projects",
                               symbolName: "folder",
                               message: "Run a scan to find build artifacts.") {
                    if !model.scanState.isScanning {
                        Button("Scan", systemImage: "magnifyingglass") { model.scan() }
                            .buttonStyle(.glassProminent)
                    }
                }
            } else {
                table
            }
        }
        .navigationTitle("Projects")
        .searchable(text: $model.searchText, prompt: "Search projects")
        .toolbar {
            ToolbarItem { ProjectFilterMenu() }
            ToolbarItem {
                Button("Inspector", systemImage: "sidebar.trailing") { model.showInspector.toggle() }
                    .help("Toggle inspector (⌘I)")
            }
        }
        .inspector(isPresented: $model.showInspector) {
            ProjectInspector()
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
    }

    private var table: some View {
        @Bindable var model = model
        return Table(rows, children: \.children, selection: $model.inspectedID, sortOrder: $sortOrder) {
            TableColumn("") { row in
                ProjectSelectionToggle(row: row)
            }
            .width(28)
            TableColumn("Name", value: \.name) { row in
                HStack(spacing: 6) {
                    if let project = row.project {
                        Image(systemName: "folder.fill").foregroundStyle(.secondary)
                        Text(row.name).fontWeight(.medium)
                        if model.isPinned(project) {
                            Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange)
                        }
                        if project.isStale { Text("Stale").font(.caption).foregroundStyle(.secondary) }
                    } else {
                        Text(row.name)
                    }
                }
            }
            TableColumn("Ecosystems", value: \.ecosystemNames) { row in
                HStack(spacing: 2) { ForEach(row.ecosystemIDs, id: \.self) { EcosystemIcon(ecosystemID: $0) } }
            }
            TableColumn("Last activity", value: \.lastActivitySort) { row in
                if let date = row.lastActivity {
                    Text(date, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
            }
            TableColumn("Reclaimable", value: \.bytes) { row in
                SizeText(bytes: row.bytes)
            }
            TableColumn("Risk", value: \.riskSort) { row in
                if let risk = row.risk { RiskBadge(risk: risk) }
            }
        }
        .contextMenu(forSelectionType: ProjectRow.ID.self) { ids in
            ProjectContextMenu(ids: ids)
        }
        .safeAreaInset(edge: .bottom) {
            GlassActionBar(count: model.selection.count, bytes: model.selectedBytes,
                           onClean: { model.requestClean() }, onClear: { model.clearSelection() })
        }
    }
}

private struct ProjectSelectionToggle: View {
    @Environment(AppModel.self) private var model
    let row: ProjectRow

    var body: some View {
        let targets = row.project?.candidates ?? row.candidate.map { [$0] } ?? []
        let on = !targets.isEmpty && targets.allSatisfy { model.selection.contains($0.id) }
        Toggle("Select \(row.name)", isOn: Binding(get: { on }, set: { model.setSelected(targets, $0) }))
            .labelsHidden()
    }
}

#Preview {
    ProjectsView().environment(AppModel()).frame(width: 900, height: 600)
}
