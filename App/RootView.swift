import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard, projects, caches, vault, history, rules

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

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
    @State private var selection: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbolName)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            let item = selection ?? .dashboard
            ContentUnavailableView(item.title, systemImage: item.symbolName, description: Text("Coming soon."))
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}
