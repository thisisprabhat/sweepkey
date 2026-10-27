import SweepkeyKit
import SwiftUI

struct ProjectsView: View {
    @Environment(\.appModel) private var model
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
            ToolbarItem {
                if model.scanState.isScanning {
                    Button("Stop Scan", systemImage: "stop.fill") { model.cancelScan() }
                        .help("Stop the running scan")
                } else {
                    Button("Rescan", systemImage: "arrow.clockwise") { model.scan() }
                        .help("Scan all your project folders again (⌘R)")
                }
            }
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
                        if model.rescanningProjects.contains(project.id) {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "folder.fill").foregroundStyle(.secondary)
                        }
                        Text(row.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle).layoutPriority(1)
                            .help(project.url.abbreviatingHome)
                        if model.isPinned(project) {
                            Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange)
                        }
                        if project.isStale {
                            Image(systemName: "clock.badge.exclamationmark").font(.caption).foregroundStyle(.secondary)
                                .help("Stale: not touched for a while, so its artifacts are good candidates to clean")
                        }
                    } else {
                        Text(row.name)
                    }
                }
            }
            .width(min: 200, ideal: 320)
            TableColumn("Ecosystems", value: \.ecosystemNames) { row in
                HStack(spacing: 2) { ForEach(row.ecosystemIDs, id: \.self) { EcosystemIcon(ecosystemID: $0) } }
            }
            .width(min: 60, ideal: 90, max: 140)
            TableColumn("Last activity", value: \.lastActivitySort) { row in
                if let date = row.lastActivity {
                    Text(date, format: .relative(presentation: .named))
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 90, ideal: 120, max: 160)
            TableColumn("Reclaimable", value: \.bytes) { row in
                SizeText(bytes: row.bytes)
            }
            .width(min: 80, ideal: 100, max: 130)
            TableColumn("Risk", value: \.riskSort) { row in
                if let risk = row.risk { RiskBadge(risk: risk) }
            }
            .width(min: 70, ideal: 90, max: 120)
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
    @Environment(\.appModel) private var model
    let row: ProjectRow

    var body: some View {
        let targets = row.project?.candidates ?? row.candidate.map { [$0] } ?? []
        let on = !targets.isEmpty && targets.allSatisfy { model.selection.contains($0.id) }
        Toggle("Select \(row.name)", isOn: Binding(get: { on }, set: { model.setSelected(targets, $0) }))
            .labelsHidden()
    }
}

#Preview {
    ProjectsView().environment(\.appModel, AppModel()).frame(width: 900, height: 600)
}
