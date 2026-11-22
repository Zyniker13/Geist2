import Foundation
import Testing

@testable import RecipeCore

struct RecipeIndexTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("index-tests-\(UUID().uuidString)")
    }

    private func recipe(_ id: String, title: String, tags: [String] = [], items: [String] = [])
        -> RecipeDocument
    {
        var recipe = RecipeDocument(id: id, title: title, createdAt: 1, modifiedAt: 1)
        recipe.tags = tags
        recipe.ingredientSections = [
            IngredientSection(name: "", lines: items.map { IngredientLine(item: $0) })
        ]
        return recipe
    }

    @Test func searchFindsTitlesIngredientsAndTags() async throws {
        let index = RecipeIndex(directory: tempDirectory())
        let recipes = [
            recipe("1", title: "Tomato Soup", tags: ["winter"], items: ["tomato", "onion"]),
            recipe("2", title: "Pancakes", tags: ["breakfast"], items: ["flour", "milk"]),
            recipe("3", title: "Fried Rice", tags: ["dinner"], items: ["rice", "egg"]),
        ]
        let count = try await index.rebuild(from: recipes)
        #expect(count == 3)

        #expect(try await index.search("tomato") == ["1"])
        #expect(try await index.search("flour") == ["2"])
        #expect(Set(try await index.search("winter")) == ["1"])
        #expect(try await index.search("rice") == ["3"])
        #expect(try await index.search("tomato pancakes") == [])
    }

    @Test func filtersNarrowTheSet() async throws {
        let index = RecipeIndex(directory: tempDirectory())
        var long = recipe("1", title: "Braise", tags: ["slow"])
        long.totalTime = Duration.hours(4)
        long.rating = 5
        var quick = recipe("2", title: "Stir fry", tags: ["fast"])
        quick.totalTime = Duration.minutes(15)
        quick.rating = 3
        _ = try await index.rebuild(from: [long, quick])

        #expect(try await index.filter(tag: "slow") == ["1"])
        #expect(try await index.filter(maxTotalSeconds: 3600) == ["2"])
        #expect(try await index.filter(minRating: 4) == ["1"])
        #expect(Set(try await index.filter()) == ["1", "2"])
    }

    @Test func deletedRecipesAreHidden() async throws {
        let index = RecipeIndex(directory: tempDirectory())
        var gone = recipe("1", title: "Old Soup")
        gone.deletedAt = 100
        var here = recipe("2", title: "New Soup")
        here.deletedAt = nil
        _ = try await index.rebuild(from: [gone, here])
        #expect(try await index.search("soup") == ["2"])
    }

    @Test func rebuildIsIdempotent() async throws {
        let index = RecipeIndex(directory: tempDirectory())
        let recipes = [recipe("1", title: "Tomato Soup")]
        _ = try await index.rebuild(from: recipes)
        _ = try await index.rebuild(from: recipes)
        #expect(try await index.search("tomato") == ["1"])
    }
}
