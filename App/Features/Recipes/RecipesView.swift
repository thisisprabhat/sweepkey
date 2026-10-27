import SwiftUI

private enum Recipe: String, CaseIterable, Identifiable {
    case freeUp, archive, migrate
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .freeUp: "Free Up Space"
        case .archive: "Archive a Project"
        case .migrate: "Move to a New Mac"
        }
    }

    var symbolName: String {
        switch self {
        case .freeUp: "gauge.with.dots.needle.bottom.50percent"
        case .archive: "archivebox"
        case .migrate: "macbook.and.arrow.forward"
        }
    }

    /// When to reach for it, in the user's words.
    var whenToUse: LocalizedStringKey {
        switch self {
        case .freeUp: "Your disk is nearly full and you need a set amount of space back."
        case .archive: "You're done with a project but want to keep it."
        case .migrate: "You're setting up another Mac and want your projects and secrets there."
        }
    }

    var steps: [LocalizedStringKey] {
        switch self {
        case .freeUp: ["Pick how much space you need", "Sweepkey plans the safest items first", "Review the plan, then clean"]
        case .archive: ["Save the project's secrets to a vault", "Delete its rebuildable folders", "Optionally zip it and trash the original"]
        case .migrate: ["Collect secrets from all projects", "List every git repo and where it lives", "Run restore.sh on the new Mac"]
        }
    }
}

/// Recipes are guided, multi-step jobs built from Sweepkey's cleaning and vault features.
struct RecipesView: View {
    @State private var recipe = Recipe.freeUp

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recipes").font(.title2.weight(.semibold))
                    Text("Recipes are guided, step-by-step jobs for common situations. Each one combines cleaning and the vault, plans everything first, and shows you the result before anything is deleted.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Recipe.allCases) { item in
                        RecipeCard(recipe: item, isSelected: recipe == item) {
                            withAnimation(.smooth) { recipe = item }
                        }
                    }
                }
                Divider()
                switch recipe {
                case .freeUp: FreeUpRecipeView()
                case .archive: ArchiveRecipeView()
                case .migrate: MigrationRecipeView()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Recipes")
    }
}

private struct RecipeCard: View {
    let recipe: Recipe
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: recipe.symbolName)
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
                    .frame(width: 42, height: 42)
                    .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tint.opacity(0.14)), in: .rect(cornerRadius: 10))
                Text(recipe.title).font(.headline)
                Text(recipe.whenToUse).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(index + 1)").font(.caption2.weight(.bold)).foregroundStyle(.tint)
                                .frame(width: 14)
                            Text(step).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(14)
            .contentShape(.rect)
            .background(.quaternary.opacity(hovering || isSelected ? 0.9 : 0.5), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    RecipesView().environment(\.appModel, AppModel()).frame(width: 860, height: 640)
}
