import RecipeCore
import XCTest

@testable import RecipeApp

/// The editor model (M4.3): row composition re-parses through the M2
/// parser, pasted lines become rows, and save writes through the store.
@MainActor
final class RecipeEditorModelTests: XCTestCase {
    private var root: URL!
    private var library: LibraryModel!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("editor-tests-\(UUID().uuidString)")
        library = LibraryModel(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Composition

    func testRowComposesParseableText() {
        let row = EditableIngredientRow(
            amount: "2", unit: "cups", item: "flour", preparation: "sifted")
        let line = IngredientParser.parse(row.text)
        XCTAssertEqual(line.quantity?.amount, 2)
        XCTAssertEqual(line.unitID, "cup")
        XCTAssertEqual(line.item, "flour")
        XCTAssertEqual(line.preparation, "sifted")
    }

    func testRowRangeComposesWithTo() {
        let row = EditableIngredientRow(
            amount: "2 – 3", unit: "cloves", item: "garlic")
        let line = IngredientParser.parse(row.text)
        XCTAssertEqual(line.quantity?.amount, 2)
        XCTAssertEqual(line.quantityHigh?.amount, 3)
    }

    func testRowToTasteHasNoQuantity() {
        let row = EditableIngredientRow(item: "salt", toTaste: true)
        let line = IngredientParser.parse(row.text)
        XCTAssertTrue(line.toTaste)
        XCTAssertNil(line.quantity)
    }

    // MARK: Paste

    func testPasteCreatesRowsAndSections() {
        let model = RecipeEditorModel(recipe: nil, library: library)
        let added = model.pasteIngredientLines(
            """
            2 cups flour
            1 tsp salt

            For the glaze:
            2 tbsp honey
            """, into: 0)
        XCTAssertEqual(added, 3)
        XCTAssertEqual(model.ingredientSections.count, 2)
        XCTAssertEqual(model.ingredientSections[0].name, "")
        XCTAssertEqual(model.ingredientSections[0].rows.count, 2)
        XCTAssertEqual(model.ingredientSections[1].name, "For the glaze")
        XCTAssertEqual(model.ingredientSections[1].rows.count, 1)
        XCTAssertEqual(model.ingredientSections[1].rows[0].amount, "2")
        XCTAssertEqual(model.ingredientSections[1].rows[0].unit, "tbsp")
    }

    func testPasteIntoEmptyModelStartsFromNothing() {
        let model = RecipeEditorModel(recipe: nil, library: library)
        model.pasteIngredientLines("1 egg", into: 0)
        XCTAssertEqual(model.ingredientSections[0].rows[0].item, "egg")
    }

    // MARK: Save

    func testSaveWritesThroughStoreAndParsesRows() async throws {
        let model = RecipeEditorModel(recipe: nil, library: library)
        model.document.title = "Test Cake"
        model.ingredientSections[0].rows[0] = EditableIngredientRow(
            amount: "1 1/2", unit: "cups", item: "flour")
        model.stepSections[0].steps[0].text = "Bake for 35 minutes."
        try await model.save()

        let stored = try XCTUnwrap(library.recipes.first { $0.title == "Test Cake" })
        let line = try XCTUnwrap(stored.ingredientSections.first?.lines.first)
        XCTAssertEqual(line.quantity?.amount, 1.5)
        XCTAssertEqual(line.unitID, "cup")
        XCTAssertEqual(line.originalText, "1 1/2 cups flour")
        // The step's timer was detected from the text.
        XCTAssertEqual(
            stored.stepSections.first?.steps.first?.timers,
            [RecipeCore.Duration.minutes(35)])
        // The store stamped modifiedAt.
        XCTAssertGreaterThan(stored.modifiedAt, 0)
    }

    func testSaveWithoutTitleIsBlocked() async throws {
        let model = RecipeEditorModel(recipe: nil, library: library)
        XCTAssertFalse(model.canSave)
        model.document.title = "Named"
        XCTAssertTrue(model.canSave)
    }

    func testEditExistingRecipeKeepsIdentity() async throws {
        var recipe = RecipeDocument(
            id: "existing-1", title: "Old Title",
            createdAt: 1_000, modifiedAt: 1_000)
        recipe.ingredientSections = [
            IngredientSection(name: "", lines: [IngredientParser.parse("2 cups oats")])
        ]
        try await library.store.write(recipe)
        await library.refresh()

        let model = RecipeEditorModel(recipe: recipe, library: library)
        model.document.title = "New Title"
        model.ingredientSections[0].rows[0].amount = "3"
        try await model.save()

        let stored = try XCTUnwrap(library.recipes.first { $0.id == "existing-1" })
        XCTAssertEqual(stored.title, "New Title")
        XCTAssertEqual(stored.ingredientSections.first?.lines.first?.quantity?.amount, 3)
        // Same identity: createdAt survived the edit.
        XCTAssertEqual(stored.createdAt, 1_000)
    }

    // MARK: Yield parsing

    func testYieldAmountParsing() {
        XCTAssertEqual(RecipeEditorModel.yieldAmount(from: "4"), 4)
        XCTAssertEqual(RecipeEditorModel.yieldAmount(from: "1 1/2"), Decimal(string: "1.5")!)
        XCTAssertNil(RecipeEditorModel.yieldAmount(from: ""))
        XCTAssertNil(RecipeEditorModel.yieldAmount(from: "lots"))
    }
}
