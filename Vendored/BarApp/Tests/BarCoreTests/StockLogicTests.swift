import GRDB
import Testing

@testable import BarCore

@Suite
struct StockLogicTests {
    // MARK: - Fixtures

    private func makeDatabase() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.setupTaxonomy()
        return db
    }

    private func product(
        _ db: AppDatabase,
        id: String,
        name: String,
        taxonomyId: String?,
        threshold: Int? = nil
    ) throws {
        try db.saveProduct(
            ProductRecord(
                id: id, taxonomyId: taxonomyId, name: name,
                lowStockThreshold: threshold,
                createdAt: 100, modifiedAt: 100))
    }

    private func bottle(
        _ db: AppDatabase,
        id: String,
        productId: String,
        status: InventoryItemRecord.Status
    ) throws {
        try db.saveInventoryItem(
            InventoryItemRecord(
                id: id, productId: productId, status: status,
                createdAt: 100, modifiedAt: 100))
    }

    private func recipe(
        _ db: AppDatabase,
        id: String,
        ingredientIds: [(String, Bool)]
    ) throws {
        let record = RecipeRecord(
            id: id,
            name: id,
            instructions: "Stir.",
            tags: ["classic"],
            ingredients: ingredientIds.enumerated().map { index, line in
                RecipeIngredientRecord(
                    ordinal: index,
                    taxonomyId: line.0,
                    label: line.0,
                    isOptional: false,
                    isGarnish: line.1)
            })
        // Library origin is the shortest real path to recipe rows in the
        // store; the restock query only joins on the recipe table.
        try db.replaceLibraryRecipes(
            [record], moduleId: "test-module", moduleVersion: 1, moduleTitle: "Test")
    }

    // MARK: Threshold resolution

    @Test func thresholdPrefersProductThenNearestAncestorThenDefault() {
        let categoryThresholds = ["spirit.gin": 2]
        let parentByNode: [String: String?] = [
            "spirit.gin.genever": "spirit.gin",
            "spirit.gin": "spirit",
            "spirit": String?.none,
        ]

        // Product override wins over everything.
        #expect(
            StockLogic.threshold(
                productId: "p", productThreshold: 0, productTaxonomyId: "spirit.gin.genever",
                categoryThresholds: categoryThresholds, parentByNode: parentByNode) == 0)
        // A leaf walks up to the nearest category with a threshold.
        #expect(
            StockLogic.threshold(
                productId: "p", productThreshold: nil, productTaxonomyId: "spirit.gin.genever",
                categoryThresholds: categoryThresholds, parentByNode: parentByNode) == 2)
        // A node with no ancestor threshold gets the built-in default.
        #expect(
            StockLogic.threshold(
                productId: "p", productThreshold: nil, productTaxonomyId: "spirit",
                categoryThresholds: categoryThresholds, parentByNode: parentByNode)
                == StockLogic.defaultThreshold)
    }

    // MARK: Low stock

    @Test func lowStockCountsOnHandBottlesOnly() throws {
        let db = try makeDatabase()
        try product(db, id: "gin", name: "Genever", taxonomyId: "spirit.gin.genever", threshold: 2)
        try bottle(db, id: "i1", productId: "gin", status: .opened)
        try bottle(db, id: "i2", productId: "gin", status: .finished)
        try bottle(db, id: "i3", productId: "gin", status: .wishlist)

        let parentByNode: [String: String?] = [
            "spirit.gin.genever": "spirit.gin", "spirit.gin": "spirit", "spirit": String?.none,
        ]
        let low = StockLogic.lowStockProducts(
            products: try db.products(),
            items: try db.inventoryItems(),
            categoryThresholds: [:],
            parentByNode: parentByNode)
        // Threshold 2, on hand = opened only (finished and wishlist don't
        // count) → low, with 1 of 2.
        #expect(low.count == 1)
        #expect(low.first?.onHand == 1)
        #expect(low.first?.threshold == 2)
    }

    @Test func stockAtOrAboveThresholdIsNotLow() throws {
        let db = try makeDatabase()
        try product(db, id: "gin", name: "Genever", taxonomyId: "spirit.gin.genever")
        try bottle(db, id: "i1", productId: "gin", status: .unopened)

        let parentByNode: [String: String?] = [
            "spirit.gin.genever": "spirit.gin", "spirit.gin": "spirit", "spirit": String?.none,
        ]
        let low = StockLogic.lowStockProducts(
            products: try db.products(),
            items: try db.inventoryItems(),
            categoryThresholds: [:],
            parentByNode: parentByNode)
        #expect(low.isEmpty)
    }

    // MARK: Restock drafts

    @Test func draftsCoverLowStockAndMissingIngredients() throws {
        let db = try makeDatabase()
        // Genever bottle covers a "spirit.gin" ask; nothing covers lemon.
        try product(db, id: "gin", name: "Genever", taxonomyId: "spirit.gin.genever")
        try bottle(db, id: "i1", productId: "gin", status: .opened)
        // Sweet vermouth with no bottles at all → low.
        try product(
            db, id: "vermouth", name: "Sweet Vermouth", taxonomyId: "fortified-wine.vermouth.sweet")
        try recipe(
            db, id: "martini-test",
            ingredientIds: [
                ("spirit.gin", false), ("fortified-wine.vermouth.sweet", false),
                ("mixer.juice.lemon", false), ("pantry.garnish.olive", true),
            ])

        let drafts = try db.restockDrafts(chosenRecipeIds: ["martini-test"])
        let byLabel = Dictionary(uniqueKeysWithValues: drafts.map { ($0.label, $0) })
        // Low stock: vermouth (no bottles).
        #expect(byLabel["Sweet Vermouth"]?.reason == .lowStock)
        // Missing: lemon (no bottle covers mixer.juice.lemon), with the
        // recipe id attached.
        #expect(byLabel["Lemon Juice"]?.reason == .missingIngredient(recipeId: "martini-test"))
        // The label comes from the taxonomy node, not the ingredient line.
        #expect(
            drafts.contains {
                $0.taxonomyId == "mixer.juice.lemon"
                    && $0.reason == .missingIngredient(recipeId: "martini-test")
            })
        // Covered: gin (the genever bottle satisfies the broader ask) and
        // the garnish (excluded from missing-ingredient logic).
        #expect(byLabel["Genever"] == nil)
        #expect(byLabel["pantry.garnish.olive"] == nil)
    }

    @Test func draftsMergeAndDedupeAgainstTheList() throws {
        let db = try makeDatabase()
        // The vermouth is both low-stock and missing from the recipe: one
        // merged draft, low-stock reason.
        try product(
            db, id: "vermouth", name: "Sweet Vermouth", taxonomyId: "fortified-wine.vermouth.sweet")
        try recipe(db, id: "martini-2", ingredientIds: [("fortified-wine.vermouth.sweet", false)])

        let drafts = try db.restockDrafts(chosenRecipeIds: ["martini-2"])
        #expect(drafts.count == 1)
        #expect(drafts.first?.reason == .lowStock)

        let list = try db.defaultShoppingList()
        #expect(try db.addRestockDrafts(drafts, toListId: list.id) == 1)
        // A second pass adds nothing while the item is unchecked.
        #expect(try db.addRestockDrafts(drafts, toListId: list.id) == 0)

        // Checking the item off reopens the door for a later restock.
        let items = try db.shoppingListItems(listId: list.id)
        try db.setShoppingListItemChecked(itemId: items[0].id, checked: true)
        #expect(try db.addRestockDrafts(drafts, toListId: list.id) == 1)
    }
}
