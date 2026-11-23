import RecipeCore
import XCTest

final class LibraryQueryTests: XCTestCase {
    private func recipe(
        _ title: String, tags: [String] = [], categories: [String] = [],
        cuisine: String? = nil, total: Int? = nil, modifiedAt: Int64 = 0,
        rating: Int = 0, ingredientItem: String? = nil
    ) -> RecipeDocument {
        var doc = RecipeDocument(
            id: "id-\(title)", title: title, createdAt: 1_000, modifiedAt: modifiedAt)
        doc.tags = tags
        doc.categories = categories
        doc.cuisine = cuisine
        if let total { doc.totalTime = Duration(seconds: total) }
        doc.rating = rating
        doc.summary = "\(title) summary"
        if let ingredientItem {
            doc.ingredientSections = [
                IngredientSection(
                    name: "",
                    lines: [
                        IngredientLine(item: ingredientItem, originalText: "1 \(ingredientItem)")
                    ])
            ]
        }
        return doc
    }

    func testEmptyQueryKeepsEverythingSortedNewestFirst() {
        let docs = [
            recipe("A", modifiedAt: 3),
            recipe("B", modifiedAt: 9),
            recipe("C", modifiedAt: 1),
        ]
        let out = LibraryQuerying.apply(LibraryQuery(), to: docs)
        XCTAssertEqual(out.map(\.title), ["B", "A", "C"])
    }

    func testTextSearchMatchesTitleIngredientsAndTags() {
        let soup = recipe("Lentil Soup", tags: ["weeknight"], ingredientItem: "lentils")
        let cards = recipe("Spiced Cards", ingredientItem: "cardamom")
        let out = LibraryQuerying.apply(
            LibraryQuery(text: "lentils"),
            to: [soup, cards])
        XCTAssertEqual(out.map(\.title), ["Lentil Soup"])
    }

    func testEveryTermMustMatch() {
        let soup = recipe("Lentil Soup", tags: ["weeknight"])
        let out = LibraryQuerying.apply(
            LibraryQuery(text: "lentil soup"),
            to: [soup, recipe("Lentil Salad")])
        XCTAssertEqual(out.map(\.title), ["Lentil Soup"])
    }

    func testTagCategoryCuisineFilters() {
        let a = recipe("A", tags: ["quick"], categories: ["Mains"], cuisine: "Italian")
        let b = recipe("B", tags: ["quick"])
        let c = recipe("C", categories: ["Mains"])
        XCTAssertEqual(
            LibraryQuerying.apply(LibraryQuery(tag: "quick"), to: [a, b, c])
                .map(\.title), ["A", "B"])
        XCTAssertEqual(
            LibraryQuerying.apply(LibraryQuery(category: "Mains"), to: [a, b, c])
                .map(\.title), ["A", "C"])
        XCTAssertEqual(
            LibraryQuerying.apply(LibraryQuery(cuisine: "Italian"), to: [a, b, c])
                .map(\.title), ["A"])
    }

    func testTimeAndRatingFilters() {
        let fast = recipe("Fast", total: 900, rating: 4)
        let slow = recipe("Slow", total: 7_200, rating: 2)
        let untimed = recipe("Untimed", rating: 5)
        XCTAssertEqual(
            LibraryQuerying.apply(LibraryQuery(maxTotalSeconds: 3_600), to: [fast, slow, untimed])
                .map(\.title), ["Fast"])
        // Default sort (newest) with tied timestamps falls back to
        // title order, so the result is Fast, Untimed.
        XCTAssertEqual(
            LibraryQuerying.apply(LibraryQuery(minRating: 3), to: [fast, slow, untimed])
                .map(\.title), ["Fast", "Untimed"])
    }

    func testSortOrders() {
        let a = recipe("banana", modifiedAt: 1, rating: 1)
        let b = recipe("Apple", modifiedAt: 2, rating: 5)
        XCTAssertEqual(
            LibraryQuerying.apply(LibraryQuery(sort: .title), to: [a, b]).map(\.title),
            ["Apple", "banana"])
        XCTAssertEqual(
            LibraryQuerying.apply(LibraryQuery(sort: .oldest), to: [a, b]).map(\.title),
            ["banana", "Apple"])
        XCTAssertEqual(
            LibraryQuerying.apply(LibraryQuery(sort: .rating), to: [a, b]).map(\.title),
            ["Apple", "banana"])
    }

    func testIsNarrowedDistinguishesFiltersFromSort() {
        XCTAssertFalse(LibraryQuery().isNarrowed)
        XCTAssertFalse(LibraryQuery(sort: .title).isNarrowed)
        XCTAssertTrue(LibraryQuery(text: "soup").isNarrowed)
        XCTAssertTrue(LibraryQuery(tag: "quick").isNarrowed)
    }
}
