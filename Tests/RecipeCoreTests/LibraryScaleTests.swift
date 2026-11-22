import Foundation
import Testing

@testable import RecipeCore

/// M1's "Done when" performance proof: a 5,000-recipe generated library
/// opens and searches in under 50 ms on the Mac.
struct LibraryScaleTests {
    private func tempRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("library-scale-\(UUID().uuidString)")
    }

    /// Generates `count` varied recipes deterministically (no UUID(), no
    /// Date(): RecipeCore stays deterministic).
    private func generatedRecipes(_ count: Int) -> [RecipeDocument] {
        let ingredients = [
            "flour", "milk", "eggs", "butter", "sugar", "onion", "garlic",
            "tomato", "chicken", "rice", "beans", "cheese", "lemon", "salt",
            "olive oil", "paprika", "cumin", "potato", "carrot", "celery",
        ]
        let methods = ["simmer", "bake", "fry", "roast", "grill", "steam"]
        return (0..<count).map { index in
            var recipe = RecipeDocument(
                id: "r\(index)", title: "Recipe \(index) \(methods[index % methods.count])",
                createdAt: 1, modifiedAt: 1)
            recipe.summary = "A test recipe number \(index)."
            recipe.tags = ["tag\(index % 10)", "tag\(index % 3)"]
            recipe.cuisine = index % 2 == 0 ? "one" : "two"
            recipe.rating = index % 6
            recipe.totalTime = RecipeCore.Duration(seconds: index % 120 * 60)
            recipe.ingredientSections = [
                IngredientSection(
                    name: "",
                    lines: (0..<6).map { line in
                        IngredientLine(
                            item: ingredients[(index * 7 + line) % ingredients.count],
                            originalText: "line")
                    })
            ]
            recipe.stepSections = [
                StepSection(
                    name: "",
                    steps: (0..<4).map { step in
                        Step(text: "Step \(step) for recipe \(index).")
                    })
            ]
            return recipe
        }
    }

    @Test func searchOver5000RecipesIsUnder50ms() async throws {
        let root = tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root, clock: .live)
        let recipes = generatedRecipes(5_000)

        // Write through the store (files on disk), then build the index.
        for recipe in recipes {
            try await store.write(recipe)
        }
        let index = RecipeIndex(directory: root.appendingPathComponent("Index"))
        let indexed = try await index.rebuild(from: recipes)
        #expect(indexed == 5_000)

        // Warm the database pool once, then measure repeated searches.
        _ = try await index.search("recipe")
        var slowest: Swift.Duration = .zero
        let queries = ["tomato", "flour milk", "simmer", "recipe 499", "garlic roast"]
        for query in queries {
            let clock = Swift.ContinuousClock()
            let start = clock.now
            _ = try await index.search(query)
            let elapsed = clock.now - start
            slowest = max(slowest, elapsed)
        }
        let ms =
            (Double(slowest.components.seconds) * 1000) + Double(slowest.components.attoseconds)
            / 1e15
        #expect(ms < 50, "slowest search took \(ms) ms")
    }
}
