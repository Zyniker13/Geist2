import Foundation
import Testing

@testable import RecipeCore

/// Parser tests over hand-written cases (the 500-line corpus lives in
/// IngredientCorpusTests, generated from a table).
struct IngredientParserTests {
    private func parse(_ text: String) -> IngredientLine {
        IngredientParser.parse(text)
    }

    @Test func integersDecimalsAndFractions() {
        #expect(parse("2 cups flour").quantity?.amount == 2)
        #expect(parse("2 cups flour").unitID == "cup")
        #expect(parse("2 cups flour").item == "flour")
        #expect(parse("1.5 lb chicken").quantity?.amount == 1.5)
        #expect(parse("1.5 lb chicken").unitID == "lb")
        #expect(parse("3/4 cup milk").quantity?.amount == 0.75)
        #expect(parse("½ tsp salt").quantity?.amount == 0.5)
        #expect(parse("2½ cups flour").quantity?.amount == 2.5)
        #expect(parse("1-1/2 cups flour").quantity?.amount == 1.5)
    }

    @Test func ranges() {
        let line = parse("2 to 3 cloves garlic")
        #expect(line.quantity?.amount == 2)
        #expect(line.quantityHigh?.amount == 3)
        #expect(line.unitID == "clove")
        #expect(line.item == "garlic")
    }

    @Test func articlesAndHalfWord() {
        #expect(parse("a pinch salt").quantity?.amount == 1)
        #expect(parse("a pinch salt").unitID == "pinch")
        #expect(parse("an onion").quantity?.amount == 1)
        #expect(parse("an onion").unitID == nil)
        #expect(parse("half lemon").quantity?.amount == 0.5)
    }

    @Test func unitVariants() {
        #expect(parse("2 tablespoons olive oil").unitID == "tbsp")
        #expect(parse("2 tbsp olive oil").unitID == "tbsp")
        #expect(parse("2 T olive oil").unitID == "tbsp")
        #expect(parse("1 teaspoon vanilla").unitID == "tsp")
        #expect(parse("8 fl oz cream").unitID == "oz")
        #expect(parse("8 oz cream cheese").unitID == "ozm")
        #expect(parse("8 ozm chocolate").unitID == "ozm")
        #expect(parse("1 stick butter").unitID == "stick")
    }

    @Test func preparationNoteAndOptional() {
        let line = parse("2 cups onions, finely chopped (about 1 large)")
        #expect(line.item == "onions")
        #expect(line.preparation == "finely chopped")
        #expect(line.note == "about 1 large")
        let optional = parse("1/4 cup parsley, chopped (optional)")
        #expect(optional.optional)
    }

    @Test func toTasteHasNoQuantity() {
        let line = parse("salt to taste")
        #expect(line.toTaste)
        #expect(line.quantity == nil)
        #expect(line.item == "salt")
    }

    @Test func sectionHeaders() {
        #expect(IngredientParser.isSectionHeader("For the marinade:"))
        #expect(IngredientParser.isSectionHeader("Dressing"))
        #expect(!IngredientParser.isSectionHeader("2 cups flour"))
        #expect(!IngredientParser.isSectionHeader("1 onion: diced"))
    }

    @Test func unparseableLinesRoundTrip() {
        let line = parse("A handful of whatever you like")
        #expect(line.quantity == nil)
        #expect(line.item == "A handful of whatever you like")
        #expect(line.originalText == "A handful of whatever you like")
    }

    @Test func sizesAttachToItem() {
        let line = parse("3 large eggs")
        #expect(line.quantity?.amount == 3)
        #expect(line.item == "large eggs")
    }
}
