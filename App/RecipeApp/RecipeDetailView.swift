import RecipeCore
import SwiftUI

/// Loads a recipe by ID and shows it. The detail view itself is M4
/// work; M3 ships a readable first pass so imports can be checked.
struct RecipeDetailLoader: View {
    @EnvironmentObject private var library: LibraryModel
    let recipeID: String

    var body: some View {
        if let recipe = library.recipes.first(where: { $0.id == recipeID }) {
            RecipeDetailView(recipe: recipe)
        } else {
            ContentUnavailableView("Recipe not found", systemImage: "questionmark.folder")
        }
    }
}

struct RecipeDetailView: View {
    @EnvironmentObject private var library: LibraryModel
    let recipe: RecipeDocument

    var body: some View {
        List {
            if !recipe.summary.isEmpty {
                Text(recipe.summary).foregroundStyle(.secondary)
            }
            facts
            ForEach(recipe.ingredientSections, id: \.name) { section in
                Section(section.name.isEmpty ? "Ingredients" : section.name) {
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        Text(line.originalText.isEmpty ? line.item : line.originalText)
                    }
                }
            }
            ForEach(recipe.stepSections, id: \.name) { section in
                Section(section.name.isEmpty ? "Directions" : section.name) {
                    ForEach(Array(section.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(index + 1).")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(step.text)
                        }
                    }
                }
            }
        }
        .navigationTitle(recipe.title)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder private var facts: some View {
        Section {
            HStack(spacing: 12) {
                if recipe.yieldAmount != nil {
                    Label("\(recipe.yieldAmount!) \(recipe.yieldUnit)", systemImage: "person.2")
                }
                if let prep = recipe.prepTime {
                    Label(prep.shortLabel, systemImage: "knife")
                }
                if let cook = recipe.cookTime {
                    Label(cook.shortLabel, systemImage: "flame")
                }
                if let total = recipe.totalTime {
                    Label(total.shortLabel, systemImage: "clock")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if let url = recipe.sourceURL, let link = URL(string: url) {
                Link(destination: link) {
                    Label("Source", systemImage: "safari")
                        .lineLimit(1)
                }
                .font(.subheadline)
            }
        }
    }
}
