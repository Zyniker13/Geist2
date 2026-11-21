import Foundation
import Testing

@testable import RecipeCore

struct UnitCatalogTests {
    @Test func knownUnitsResolve() {
        let catalog = UnitCatalog()
        #expect(catalog.definition(matching: "cup")?.id == "cup")
        #expect(catalog.definition(matching: "Cups")?.id == "cup")
        #expect(catalog.definition(matching: "teaspoon")?.id == "tsp")
        #expect(catalog.definition(matching: "grams")?.id == "g")
    }

    @Test func volumeConversionIsExact() {
        let catalog = UnitCatalog()
        let cup = catalog.convert(1, from: "cup", to: "tbsp")!
        #expect(cup == 16)
    }

    @Test func massConversionIsExact() {
        let catalog = UnitCatalog()
        let grams = catalog.convert(1, from: "lb", to: "g")!
        #expect(grams == Decimal(string: "453.59237")!)
    }

    @Test func dimensionMismatchIsRejected() {
        let catalog = UnitCatalog()
        #expect(catalog.convert(1, from: "cup", to: "g") == nil)
    }
}

struct RecipeMathTests {
    @Test func scalingDoublesCups() throws {
        let scaled = try RecipeMath.scale(
            [RecipeMath.Ingredient(label: "flour", amount: 2, unit: "cup")],
            by: 2)
        #expect(scaled[0].amount == 4)
    }

    @Test func scaledDownPinchNeverDisappears() throws {
        let scaled = try RecipeMath.scale(
            [RecipeMath.Ingredient(label: "salt", amount: 1, unit: "pinch")],
            by: Decimal(string: "0.5")!)
        #expect(scaled[0].amount == 1)
    }

    @Test func badFactorThrows() {
        #expect(throws: RecipeMath.MathError.badFactor.self) {
            try RecipeMath.scale([], by: 0)
        }
    }
}
