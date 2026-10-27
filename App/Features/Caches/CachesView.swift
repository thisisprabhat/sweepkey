import SweepkeyKit
import SwiftUI

struct CachesView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        Group {
            if model.cacheGroups.isEmpty {
                EmptyStateView("No caches found", symbolName: "internaldrive",
                               message: "Run a scan to look for developer caches.") {
                    Button("Scan", systemImage: "magnifyingglass") { model.scan() }
                        .buttonStyle(.glassProminent)
                        .disabled(model.scanState.isScanning)
                }
            } else {
                List {
                    ForEach(CacheCategory.allCases, id: \.self) { category in
                        let groups = model.cacheGroups.filter { $0.category == category }
                        if !groups.isEmpty {
                            Section {
                                ForEach(groups) { CacheGroupRow(group: $0) }
                            } header: {
                                SectionHeaderView(title: LocalizedStringKey(category.displayName),
                                                  symbolName: category.symbolName) {
                                    SizeText(bytes: groups.reduce(0) { $0 + $1.totalBytes })
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    GlassActionBar(count: model.selection.count, bytes: model.selectedBytes,
                                   onClean: { model.requestClean() }, onClear: { model.clearSelection() })
                }
            }
        }
        .navigationTitle("Caches")
    }
}

#Preview {
    let model = AppModel()
    CachesView().environment(\.appModel, model).frame(width: 760, height: 600)
        .task { model.cacheGroups = MockData.cacheGroups }
}
