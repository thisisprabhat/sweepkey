import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard, projects, caches, vault, history, rules

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .dashboard: "Dashboard"
        case .projects: "Projects"
        case .caches: "Caches"
        case .vault: "Vault"
        case .history: "History"
        case .rules: "Rules"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.33percent"
        case .projects: "folder"
        case .caches: "internaldrive"
        case .vault: "lock.shield"
        case .history: "clock.arrow.circlepath"
        case .rules: "list.bullet.rectangle"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .dashboard

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbolName)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            switch selection ?? .dashboard {
            case .dashboard: DashboardView()
            case .projects: ProjectsView()
            case .caches: CachesView()
            case .vault: VaultView()
            case .history: HistoryView()
            case .rules: RulesView()
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .sheet(isPresented: $model.isCleanSheetPresented) {
            CleanFlowSheet()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
        .task {
            await model.loadJournal()
            model.scanIfNeeded()
        }
    }
}

#Preview {
    RootView().environment(AppModel())
}
