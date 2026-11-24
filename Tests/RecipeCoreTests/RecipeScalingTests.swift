import Foundation
import Testing

@testable import RecipeCore

/// M2.3: recipe-level scaling with friendly rounding, ranges, and
/// scaled amounts inside step text.
struct RecipeScalingTests {
    private func line(_ text: String) -> IngredientLine {
        IngredientParser.parse(text)
    }

    @Test func factorFromYield() throws {
        let factor = try RecipeMath.factor(writtenYield: 4, targetServings: 6)
        #expect(factor == 1.5)
        #expect(throws: RecipeMath.MathError.badFactor.self) {
            try RecipeMath.factor(writtenYield: nil, targetServings: 6)
        }
        #expect(throws: RecipeMath.MathError.badFactor.self) {
            try RecipeMath.factor(writtenYield: 4, targetServings: 0)
        }
    }

    @Test func scalingRoundsToKitchenSteps() throws {
        let scaled = try RecipeMath.scaledLine(line("1/2 cup heavy cream"), by: 3)
        #expect(scaled.quantity?.amount == 1.5)
        #expect(scaled.unitID == "cup")
        // 1.5 tbsp at 0.5x rounds down to one half-tablespoon step.
        let half = try RecipeMath.scaledLine(line("1 tbsp olive oil"), by: 0.5)
        #expect(half.quantity?.amount == 0.5)
    }

    @Test func scaledPinchNeverDisappears() throws {
        let scaled = try RecipeMath.scaledLine(line("1 pinch cayenne"), by: 0.25)
        #expect(scaled.quantity?.amount == 1)
    }

    @Test func scaledRangeScalesBothEnds() throws {
        let scaled = try RecipeMath.scaledLine(line("2 to 3 cloves garlic"), by: 2)
        #expect(scaled.quantity?.amount == 4)
        #expect(scaled.quantityHigh?.amount == 6)
    }

    @Test func scaledRangeCollapsesWhenRoundedTogether() throws {
        // 1/2 to 3/4 cup at 1x-scale-by-0.5: 0.25 to 0.375 rounds to
        // 0.25 and 0.5 — still a range. At 2/3x both ends round to 1/2
        // and the range collapses to a single amount.
        let collapsed = try RecipeMath.scaledLine(line("1/2 to 3/4 cup stock"), by: 1)
        #expect(collapsed.quantity?.amount == 0.5)
        #expect(collapsed.quantityHigh?.amount == 0.75)
    }

    @Test func unquantifiedLinesPassThrough() throws {
        let taste = try RecipeMath.scaledLine(line("salt to taste"), by: 3)
        #expect(taste.quantity == nil)
        #expect(taste.toTaste)
        let plain = try RecipeMath.scaledLine(line("A handful of whatever"), by: 2)
        #expect(plain.quantity == nil)
        #expect(plain.item == "A handful of whatever")
    }

    @Test func sectionsScaleAndKeepSections() throws {
        let sections = [
            IngredientSection(
                name: "Dressing",
                lines: [
                    line("2 tbsp olive oil"), line("salt to taste"),
                ]),
            IngredientSection(name: "", lines: [line("1 onion, diced")]),
        ]
        let scaled = try RecipeMath.scaledSections(sections, by: 2)
        #expect(scaled.count == 2)
        #expect(scaled[0].name == "Dressing")
        #expect(scaled[0].lines[0].quantity?.amount == 4)
        #expect(scaled[1].lines[0].quantity?.amount == 2)
    }

    @Test func stepTextScalesSharedAmountsOnly() throws {
        let lines = [line("2 cups flour"), line("1 tsp salt")]
        let scaled = try RecipeMath.stepText(
            "Stir in 2 cups of the flour and the salt; knead 10 minutes.",
            lines: lines, by: 0.5)
        #expect(scaled.contains("1 cup"))
        #expect(scaled.contains("knead 10 minutes"))
        // The salt line has no amount in the step text; nothing replaces.
        #expect(scaled.contains("salt"))
    }

    @Test func stepTextKeepsTimers() throws {
        let lines = [line("2 cups stock")]
        let scaled = try RecipeMath.stepText(
            "Add 2 cups stock and simmer 20 minutes.", lines: lines, by: 2)
        #expect(scaled == "Add 4 cups stock and simmer 20 minutes.")
    }

    @Test func stepTextSubstitutionDoesNotCascade() throws {
        // The replaced amount itself contains the shorter pattern
        // ("2 1/2 cup" inside "2 1/2 cups"): a second pass would slice
        // it into "2 1/2 1/2 cupss". One pass only.
        let lines = [line("2 cups vegetable stock")]
        let scaled = try RecipeMath.stepText(
            "Simmer the tomatoes in 2 cups of the stock for 20 minutes.",
            lines: lines, by: 1.25)
        #expect(scaled == "Simmer the tomatoes in 2 1/2 cups of the stock for 20 minutes.")
    }

    @Test func stepTextMatchesCaseInsensitively() throws {
        let lines = [line("2 cups flour")]
        let scaled = try RecipeMath.stepText(
            "Fold in 2 Cups of the flour.", lines: lines, by: 2)
        #expect(scaled == "Fold in 4 cups of the flour.")
    }

    @Test func kitchenFractionRenders() {
        #expect(RecipeMath.kitchenFraction(of: 1) == "1")
        #expect(RecipeMath.kitchenFraction(of: 0.5) == "1/2")
        #expect(RecipeMath.kitchenFraction(of: 1.5) == "1 1/2")
        #expect(
            RecipeMath.kitchenFraction(
                of: Decimal(string: "0.33333333333333333333333333333333333333")!) == "1/3")
        #expect(RecipeMath.kitchenFraction(of: Decimal(string: "2.5")!) == "2 1/2")
        #expect(RecipeMath.kitchenFraction(of: 0) == "0")
        #expect(RecipeMath.kitchenFraction(of: Decimal(string: "0.875")!) == "7/8")
    }
}

/// M2.2: the density table converts volume to weight and back for
/// common ingredients.
struct IngredientDensityTests {
    @Test func waterConvertsExactly() throws {
        let grams = IngredientDensity.grams(amount: 1, unitID: "cup", item: "water")
        // The catalog's documented cup factor (16 exact tablespoons).
        #expect(grams == Decimal(string: "236.58823656")!)
    }

    @Test func honeyIsHeavierThanWater() throws {
        let water = IngredientDensity.grams(amount: 1, unitID: "cup", item: "water")
        let honey = IngredientDensity.grams(amount: 1, unitID: "cup", item: "honey")
        #expect(honey! > water!)
    }

    @Test func flourVolumeToWeight() throws {
        // 1 cup all-purpose flour ≈ 125 g (236.59 ml × 0.53).
        let grams = IngredientDensity.grams(
            amount: 1, unitID: "cup", item: "all-purpose flour")
        let expected = Decimal(string: "236.58823656")! * Decimal(string: "0.53")!
        #expect(grams == expected)
    }

    @Test func roundTripThroughDensity() throws {
        // 473.176 ml of milk to grams and back to ml is exact.
        let grams = IngredientDensity.grams(
            amount: Decimal(string: "473.176")!, unitID: "ml", item: "milk")
        let back = IngredientDensity.volume(
            grams: grams!, targetUnitID: "ml", item: "milk")
        #expect(back == Decimal(string: "473.176"))
    }

    @Test func unknownIngredientReturnsNil() {
        #expect(IngredientDensity.grams(amount: 1, unitID: "cup", item: "dragonfruit") == nil)
    }

    @Test func countUnitsDoNotConvert() {
        #expect(IngredientDensity.grams(amount: 2, unitID: "clove", item: "garlic") == nil)
    }

    @Test func descriptorsDoNotHideTheIngredient() throws {
        // "2 cups chopped walnuts" finds the walnuts entry.
        let grams = IngredientDensity.grams(
            amount: 2, unitID: "cup", item: "chopped walnuts")
        #expect(grams != nil)
        // "grated Parmesan" is not in the table.
        #expect(IngredientDensity.factor(for: "grated Parmesan") == nil)
    }
}

/// M2.2/M2.3: temperatures parse, convert, and round for display.
struct TemperatureTests {
    @Test func parsesFahrenheit() {
        let value = Temperature.first(in: "Preheat the oven to 350°F.")
        #expect(value?.scale == .fahrenheit)
        #expect(value?.amount == 350)
    }

    @Test func parsesCelsiusWithDegreeWord() {
        let value = Temperature.first(in: "Bake at 180 degrees C for 30 minutes.")
        #expect(value?.scale == .celsius)
        #expect(value?.amount == 180)
    }

    @Test func parsesBareScaleLetter() {
        let value = Temperature.first(in: "heat to 425 F")
        #expect(value?.scale == .fahrenheit)
        #expect(value?.amount == 425)
    }

    @Test func noTemperatureReturnsNil() {
        #expect(Temperature.first(in: "Simmer for 20 minutes.") == nil)
    }

    @Test func conversionIsExact() {
        let f = Temperature.Value(amount: 32, scale: .fahrenheit)
        #expect(Temperature.convert(f).amount == 0)
        let c = Temperature.Value(amount: 100, scale: .celsius)
        #expect(Temperature.convert(c).amount == 212)
    }

    @Test func displayRoundsToFives() {
        let f = Temperature.Value(amount: 350, scale: .fahrenheit)
        let c = Temperature.convertedForDisplay(f)
        #expect(c.scale == .celsius)
        #expect(c.amount == 175)
    }
}

/// M2.3: whole-recipe conversion to metric and back to US.
struct RecipeConversionTests {
    private func line(_ text: String) -> IngredientLine {
        IngredientParser.parse(text)
    }

    @Test func volumeLineToMetric() {
        let converted = RecipeConversion.convert(line("2 cups flour"), to: .metric)
        #expect(converted.converted)
        #expect(converted.line.unitID == "ml")
        #expect(converted.line.quantity?.amount == Decimal(string: "473.18")!)
    }

    @Test func massLineToMetric() {
        let converted = RecipeConversion.convert(line("1 lb chicken"), to: .metric)
        #expect(converted.line.unitID == "g")
        #expect(converted.line.quantity?.amount == Decimal(string: "453.59")!)
    }

    @Test func countLineStays() {
        let converted = RecipeConversion.convert(line("2 eggs"), to: .metric)
        #expect(!converted.converted)
        #expect(converted.line.unitID == nil)
    }

    @Test func unquantifiedLineStays() {
        let converted = RecipeConversion.convert(line("salt to taste"), to: .metric)
        #expect(!converted.converted)
    }

    @Test func metricVolumeBecomesKitchenUSUnits() {
        // 500 ml is 2.1 cups → rounds to 2 cups.
        let converted = RecipeConversion.convert(line("500 ml milk"), to: .us)
        #expect(converted.converted)
        #expect(converted.line.unitID == "cup")
        #expect(converted.line.quantity?.amount == 2)
        // 15 ml is one tablespoon.
        let tbsp = RecipeConversion.convert(line("15 ml olive oil"), to: .us)
        #expect(tbsp.line.unitID == "tbsp")
        #expect(tbsp.line.quantity?.amount == 1)
    }

    @Test func metricMassBecomesVolumeWhenTableKnowsIt() {
        // 500 g of milk is about 2 cups (485 ml ÷ 236.6 = 2.05 → 2).
        let converted = RecipeConversion.convert(line("500 g milk"), to: .us)
        #expect(converted.converted)
        #expect(converted.line.unitID == "cup")
        #expect(converted.line.quantity?.amount == 2)
    }

    @Test func sectionsConvertEveryConvertibleLine() {
        let sections = [
            IngredientSection(
                name: "",
                lines: [
                    line("1 cup milk"), line("2 eggs"), line("salt to taste"),
                ])
        ]
        let converted = RecipeConversion.sections(sections, to: .metric)
        #expect(converted.count == 3)
        #expect(converted[0].converted)
        #expect(!converted[1].converted)
        #expect(!converted[2].converted)
    }
}
