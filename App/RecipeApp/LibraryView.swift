import RecipeCore
import SwiftUI

/// The library: the recipe list, the import sheet, and navigation into
/// a recipe.
struct LibraryView: View {
    @EnvironmentObject private var library: LibraryModel
    @State private var showingImport = false
    @State private var pendingLink = ""

    var body: some View {
        NavigationStack {
            Group {
                if library.recipes.isEmpty {
                    ContentUnavailableView(
                        "Your recipe library",
                        systemImage: "book.closed",
                        description: Text(
                            "Recipes you add or import will appear here."))
                } else {
                    List(library.recipes) { recipe in
                        NavigationLink(value: recipe.id) {
                            RecipeRow(recipe: recipe)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingImport = true
                    } label: {
                        Label("Import", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: String.self) { id in
                RecipeDetailLoader(recipeID: id)
            }
            .sheet(isPresented: $showingImport) {
                ImportView()
            }
            .task { await library.refresh() }
        }
    }
}

/// One row in the recipe list: title and the yield/time line.
struct RecipeRow: View {
    let recipe: RecipeDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(recipe.title.isEmpty ? "Untitled" : recipe.title)
                .font(.headline)
            HStack(spacing: 6) {
                if recipe.yieldAmount != nil {
                    Text("\(recipe.yieldAmount!) \(recipe.yieldUnit)")
                }
                if let total = recipe.totalTime {
                    Text(total.shortLabel)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

extension Duration {
    /// "1 h 30 m" for list rows.
    var shortLabel: String {
        let total = seconds / 60
        let hours = total / 60
        let minutes = total % 60
        if hours > 0 && minutes > 0 { return "\(hours) h \(minutes) m" }
        if hours > 0 { return "\(hours) h" }
        return "\(minutes) m"
    }
}

extension RecipeDocument: Identifiable {}
