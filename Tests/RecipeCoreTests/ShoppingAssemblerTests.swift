import Foundation
import RecipeCore
import Testing

/// The shopping assembler: combining across recipes, unit
/// conversion, pantry subtraction, aisle grouping, and the shown
/// line text.
struct ShoppingAssemblerTests {

    /// A minimal recipe with one section of lines.
    private func recipe(
        _ title: String,
        yield: Decimal,
        lines: [IngredientLine],
        id: String = "00000000-0000-0000-0000-000000000000"
    ) -> RecipeDocument {
        var document = RecipeDocument(id: id, title: title, createdAt: 0, modifiedAt: 0)
        document.yieldAmount = yield
        document.ingredientSections = [IngredientSection(name: "", lines: lines)]
        return document
    }

    private func line(
        _ amount: Decimal, _ unit: String?, _ item: String,
        toTaste: Bool = false, optional: Bool = false
    ) -> IngredientLine {
        IngredientLine(
            quantity: toTaste ? nil : Quantity(amount),
            quantityHigh: nil,
            unitID: toTaste ? nil : unit,
            item: item,
            preparation: nil,
            note: nil,
            optional: optional,
            toTaste: toTaste,
            originalText: "\(amount) \(unit ?? "") \(item)")
    }

    @Test func combinesAcrossThreeRecipes() throws {
        // The M5 done-when case: a three-recipe list combines.
        let soup = recipe(
            "Tomato Soup", yield: 4,
            lines: [line(2, "cup", "vegetable stock"), line(1, "lb", "tomatoes")])
        let stew = recipe(
            "Renamed Stew", yield: 4,
            lines: [line(1, "cup", "vegetable stock"), line(2, "lb", "tomatoes")])
        let braise = recipe(
            "Braise", yield: 2,
            lines: [line(500, "ml", "vegetable stock"), line(1, "lb", "onions")])

        let drafts = ShoppingAssembler.assemble(lines: [
            (soup, 4), (stew, 8), (braise, 8),
        ])
        let stock = drafts.first { $0.item == "vegetable stock" }
        #expect(stock != nil)
        // 2 cups + 2 cups (stew x2) + 2000 ml (braise x4) -> cups:
        // 2 + 2 + 8.45 = 12.45 -> snapped to quarters: 12.5.
        #expect(stock?.unitID == "cup")
        #expect(stock?.quantity == Decimal(string: "12.5"))

        let tomato = drafts.first { $0.item == "tomatoes" }
        // 1 lb + 4 lb = 5 lb.
        #expect(tomato?.quantity == 5)
        #expect(tomato?.aisle == "Produce")

        let onion = drafts.first { $0.item == "onions" }
        #expect(onion?.quantity == 4)
    }

    @Test func combinesToSingleCupsFromMixedUnits() {
        let a = recipe("A", yield: 1, lines: [line(2, "cup", "water")])
        let b = recipe("B", yield: 1, lines: [line(250, "ml", "water")])
        let drafts = ShoppingAssembler.assemble(lines: [(a, 1), (b, 1)])
        let water = drafts.first { $0.item == "water" }
        // 2 cups + 250 ml (= 1.057 cups) -> 3.057 -> snapped: 3 cups.
        #expect(water?.unitID == "cup")
        #expect(water?.quantity == 3)
    }

    @Test func keepsInconvertibleUnitsApart() {
        let a = recipe("A", yield: 1, lines: [line(2, "cup", "flour")])
        let b = recipe("B", yield: 1, lines: [line(300, "g", "flour")])
        let drafts = ShoppingAssembler.assemble(lines: [(a, 1), (b, 1)])
        // cup and gram share no density here: two lines.
        let flour = drafts.filter { $0.item == "flour" }
        #expect(flour.count == 2)
    }

    @Test func pantryCoversWholeLine() {
        let soup = recipe(
            "Soup", yield: 4,
            lines: [line(2, "cup", "vegetable stock"), line(1, "lb", "tomatoes")])
        let drafts = ShoppingAssembler.assemble(
            lines: [(soup, 4)],
            pantry: [
                ShoppingAssembler.PantryStock(name: "vegetable stock", amount: 4, unitID: "cup"),
                ShoppingAssembler.PantryStock(name: "tomatoes"),
            ])
        // Both lines vanish: stock covered by amount, tomatoes by name.
        let visible = drafts.filter { !$0.coveredByPantry }
        #expect(visible.isEmpty)
    }

    @Test func pantryPartiallyCovers() {
        let soup = recipe("Soup", yield: 4, lines: [line(3, "lb", "tomatoes")])
        let drafts = ShoppingAssembler.assemble(
            lines: [(soup, 4)],
            pantry: [ShoppingAssembler.PantryStock(name: "tomatoes", amount: 1, unitID: "lb")])
        let tomato = drafts.first { $0.item == "tomatoes" }
        #expect(tomato?.quantity == 2)
        #expect(tomato?.coveredByPantry == false)
    }

    @Test func pantryWordPrefixMatches() {
        let stew = recipe("Stew", yield: 4, lines: [line(2, "lb", "chicken thighs")])
        let drafts = ShoppingAssembler.assemble(
            lines: [(stew, 4)],
            pantry: [ShoppingAssembler.PantryStock(name: "chicken")])
        let visible = drafts.filter { !$0.coveredByPantry }
        #expect(visible.isEmpty)
    }

    @Test func toTasteLinesStayFree() {
        let soup = recipe(
            "Soup", yield: 4,
            lines: [line(0, nil, "salt", toTaste: true), line(2, "cup", "stock")])
        let drafts = ShoppingAssembler.assemble(lines: [(soup, 4)])
        let salt = drafts.first { $0.item == "salt" }
        #expect(salt?.free == true)
        #expect(salt?.quantity == nil)
        #expect(ShoppingAssembler.text(for: salt ?? drafts[0]) == "salt to taste")
    }

    @Test func optionalLinesAreSkipped() {
        let soup = recipe(
            "Soup", yield: 4,
            lines: [line(1, "cup", "cream", optional: true), line(2, "cup", "stock")])
        let drafts = ShoppingAssembler.assemble(lines: [(soup, 4)])
        #expect(drafts.first { $0.item == "cream" } == nil)
        #expect(drafts.count == 1)
    }

    @Test func scalesByServings() throws {
        let soup = recipe("Soup", yield: 4, lines: [line(2, "cup", "stock")])
        // Double the people: double the stock.
        let drafts = ShoppingAssembler.assemble(lines: [(soup, 8)])
        #expect(drafts.first?.quantity == 4)
    }

    @Test func listLinesDropCoveredAndKeepAisle() {
        let soup = recipe("Soup", yield: 4, lines: [line(2, "cup", "stock")])
        let drafts = ShoppingAssembler.assemble(
            lines: [(soup, 4)],
            pantry: [ShoppingAssembler.PantryStock(name: "stock", amount: 2, unitID: "cup")])
        let lines = ShoppingAssembler.listLines(from: drafts)
        #expect(lines.isEmpty)

        let open = ShoppingAssembler.assemble(lines: [(soup, 4)])
        let lines2 = ShoppingAssembler.listLines(from: open)
        #expect(lines2.count == 1)
        #expect(lines2[0].aisle == "Canned & Jarred")
        #expect(lines2[0].text.contains("2 cups stock"))
        #expect(lines2[0].checked == false)
    }

    @Test func aislesLandWhereExpected() {
        #expect(AisleCatalog.aisle(for: "tomatoes") == "Produce")
        #expect(AisleCatalog.aisle(for: "chicken thighs") == "Meat")
        #expect(AisleCatalog.aisle(for: "butter") == "Dairy & Eggs")
        #expect(AisleCatalog.aisle(for: "olive oil") == "Canned & Jarred")
        #expect(AisleCatalog.aisle(for: "soy sauce") == "Canned & Jarred")
        #expect(AisleCatalog.aisle(for: "flour") == "Dry goods")
        #expect(AisleCatalog.aisle(for: "frozen peas") == "Frozen")
        #expect(AisleCatalog.aisle(for: "quicksilver") == "Other")
    }

    @Test func preparationTailsDoNotSplitLines() {
        let a = recipe("A", yield: 1, lines: [line(1, "cup", "grated parmesan")])
        let b = recipe("B", yield: 1, lines: [line(1, "cup", "parmesan, grated")])
        let drafts = ShoppingAssembler.assemble(lines: [(a, 1), (b, 1)])
        #expect(drafts.filter { $0.item.contains("parmesan") }.count == 1)
        #expect(drafts.first?.quantity == 2)
    }
}
