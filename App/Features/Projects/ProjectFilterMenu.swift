import CleanerKit
import SwiftUI

struct ProjectFilterMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Menu("Filter", systemImage: model.hasActiveFilters
             ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle") {
            Picker("Ecosystem", selection: $model.ecosystemFilter) {
                Text("Any ecosystem").tag(String?.none)
                ForEach(model.availableEcosystems) { eco in
                    Label(eco.name, systemImage: eco.symbolName).tag(String?.some(eco.id))
                }
            }
            Picker("Risk", selection: $model.riskFilter) {
                Text("Any risk").tag(RiskLevel?.none)
                ForEach(RiskLevel.allCases, id: \.self) { Text($0.title).tag(RiskLevel?.some($0)) }
            }
            Picker("Minimum size", selection: $model.minSizeMB) {
                Text("Any size").tag(0)
                Text("100 MB").tag(100)
                Text("500 MB").tag(500)
                Text("1 GB").tag(1024)
            }
            Toggle("Stale projects only", isOn: $model.staleOnly)
            Divider()
            Button("Reset Filters") { model.resetFilters() }
                .disabled(!model.hasActiveFilters)
        }
        .help("Filter projects")
    }
}

#Preview {
    ProjectFilterMenu().environment(AppModel()).padding()
}
