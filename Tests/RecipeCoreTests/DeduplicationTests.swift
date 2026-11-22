import Foundation
import Testing

@testable import RecipeCore

struct DeduplicationTests {
    private func recipe(
        _ id: String, title: String, source: String? = nil,
        items: [String] = []
    ) -> RecipeDocument {
        var recipe = RecipeDocument(id: id, title: title, createdAt: 1, modifiedAt: 1)
        recipe.sourceURL = source
        recipe.ingredientSections = [
            IngredientSection(
                name: "",
                lines: items.map {
                    IngredientLine(item: $0, originalText: $0)
                })
        ]
        return recipe
    }

    @Test func sameSourceURLIsDuplicate() {
        let a = recipe("a", title: "Pancakes", source: "https://example.com/pancakes")
        let b = recipe(
            "b", title: "Best Pancakes",
            source: "https://EXAMPLE.com/pancakes/?utm_source=x#top")
        #expect(Deduplication.duplicates(of: a, among: [b]).count == 1)
    }

    @Test func sameTitleAndSimilarIngredientsIsDuplicate() {
        let a = recipe("a", title: "Tomato Soup", items: ["tomato", "onion", "broth", "salt"])
        let b = recipe("b", title: "tomato  soup", items: ["tomato", "onion", "broth", "pepper"])
        #expect(Deduplication.duplicates(of: a, among: [b]).count == 1)
    }

    @Test func sameTitleDifferentIngredientsIsNotDuplicate() {
        let a = recipe("a", title: "Tomato Soup", items: ["tomato", "onion", "broth"])
        let b = recipe("b", title: "Tomato Soup", items: ["chocolate", "flour", "eggs"])
        #expect(Deduplication.duplicates(of: a, among: [b]).isEmpty)
    }

    @Test func differentTitlesAreNotDuplicates() {
        let a = recipe("a", title: "Pancakes", items: ["flour", "milk", "eggs"])
        let b = recipe("b", title: "Waffles", items: ["flour", "milk", "eggs"])
        #expect(Deduplication.duplicates(of: a, among: [b]).isEmpty)
    }

    @Test func mergeKeepsBothSidesFields() {
        var a = recipe("a", title: "Pancakes", source: "https://example.com/a")
        a.rating = 4
        a.tags = ["breakfast"]
        var b = recipe("b", title: "Best Pancakes", source: "https://example.com/b")
        b.notes = "from grandma"
        b.photoHashes = ["hash1"]

        let merged = Deduplication.merge(b, into: a)
        #expect(merged.id == "a")
        #expect(merged.rating == 4)
        #expect(merged.tags == ["breakfast"])
        #expect(merged.notes == "from grandma")
        #expect(merged.photoHashes == ["hash1"])
        #expect(merged.sourceURL == "https://example.com/a")
    }

    @Test func mergePrefersEarlierCreated() {
        var a = recipe("a", title: "Pancakes")
        a.createdAt = 100
        var b = recipe("b", title: "Pancakes")
        b.createdAt = 50
        #expect(Deduplication.merge(a, into: b).createdAt == 50)
    }
}
