import SwiftUI

private enum Recipe: String, CaseIterable, Identifiable {
    case freeUp = "Free up space", archive = "Archive project", migrate = "New-Mac migration"
    var id: String { rawValue }
}

struct RecipesView: View {
    @State private var recipe = Recipe.freeUp

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Recipe", selection: $recipe) {
                    ForEach(Recipe.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                switch recipe {
                case .freeUp: FreeUpRecipeView()
                case .archive: ArchiveRecipeView()
                case .migrate: MigrationRecipeView()
                }
            }
            .padding(20)
        }
        .navigationTitle("Recipes")
    }
}

#Preview {
    RecipesView().environment(AppModel()).frame(width: 760, height: 600)
}
