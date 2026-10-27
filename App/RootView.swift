import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard, projects, caches, vault, history, rules, recipes

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .dashboard: "Dashboard"
        case .projects: "Projects"
        case .caches: "Caches"
        case .vault: "Vault"
        case .history: "History"
        case .rules: "Rules"
        case .recipes: "Recipes"
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
        case .recipes: "wand.and.stars"
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
            case .recipes: RecipesView()
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .focusedSceneValue(\.cleanScreenActive, selection == .projects || selection == .caches)
        .sheet(isPresented: $model.isCleanSheetPresented) {
            CleanFlowSheet()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { handleDrop($0) }
        .task { await model.bootstrap() }
    }
}

extension RootView {
    /// Dropping folders onto the window adds them as scan roots.
    fileprivate func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let target = self.model
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in target.addScanRoots([url]) }
            }
        }
        return true
    }
}

#Preview {
    RootView().environment(AppModel())
}
