import Foundation
import Testing

@testable import RecipeCore

/// M4.2: the display pipeline — scale, convert, render — as the recipe
/// view shows it.
struct RecipeDisplayTests {
    private func line(_ text: String) -> IngredientLine {
        IngredientParser.parse(text)
    }

    private func section(_ lines: [String], name: String = "") -> IngredientSection {
        IngredientSection(name: name, lines: lines.map(line))
    }

    // MARK: As written

    @Test func factorOneWrittenSystemShowsOriginalWording() {
        let rendered = RecipeDisplay.line(
            line("1 1/2 cups all-purpose flour"), options: .written)
        #expect(rendered.text == "1 1/2 cups all-purpose flour")
        #expect(rendered.scalable)
        #expect(!rendered.converted)
    }

    @Test func preparationNoteOptionalAndToTasteRender() {
        #expect(
            RecipeDisplay.line(
                line("2 cups onions, finely chopped (about 1 large)"), options: .written
            ).text == "2 cups onions, finely chopped (about 1 large)")
        #expect(
            RecipeDisplay.line(line("salt to taste"), options: .written).text == "salt to taste")
        #expect(
            RecipeDisplay.line(line("1 egg, (optional)"), options: .written).text.contains(
                "optional"))
        // An unparseable line round-trips verbatim at factor 1.
        let odd = IngredientLine(item: "xqzt", originalText: "a splash of xqzt")
        #expect(RecipeDisplay.line(odd, options: .written).text == "a splash of xqzt")
        // Rendered from fields (scaled), the item alone shows: an
        // unquantified line carries no amount to scale.
        let doubled = RecipeDisplay.line(
            odd, options: .init(factor: 2))
        #expect(doubled.text == "xqzt")
    }

    @Test func rangeRendersWithAnEnDash() {
        // As written, the range shows the source wording.
        let written = RecipeDisplay.line(line("2 to 3 cups water"), options: .written)
        #expect(written.text == "2 to 3 cups water")
        // Scaled, it renders from fields with an en dash.
        let scaled = RecipeDisplay.line(line("2 to 3 cups water"), options: .init(factor: 2))
        #expect(scaled.text.contains("–"))
    }

    // MARK: Scaling

    @Test func scalingIsFriendly() {
        let doubled = RecipeDisplay.line(
            line("1 1/2 cups heavy cream"), options: .init(factor: 2))
        #expect(doubled.text == "3 cups heavy cream")
        let halved = RecipeDisplay.line(line("1 cup flour"), options: .init(factor: 0.5))
        #expect(halved.text == "1/2 cup flour")
        // Count lines pluralize on the scaled amount.
        let eggs = RecipeDisplay.line(line("2 eggs"), options: .init(factor: 1.5))
        #expect(eggs.text == "3 eggs")
        let single = RecipeDisplay.line(line("2 eggs"), options: .init(factor: 0.5))
        #expect(single.text == "1 egg")
    }

    @Test func unscalableLinesSurviveScaling() {
        let toTaste = RecipeDisplay.line(line("salt to taste"), options: .init(factor: 3))
        #expect(toTaste.text == "salt, to taste")
        #expect(!toTaste.scalable)
    }

    @Test func scaledYieldText() throws {
        var recipe = RecipeDocument(id: "r", createdAt: 0, modifiedAt: 0)
        recipe.yieldAmount = 4
        recipe.yieldUnit = "servings"
        #expect(RecipeDisplay.yieldText(recipe, options: .written) == "4 servings")
        let tripled = try RecipeDisplay.yieldText(
            recipe, options: .init(factor: 1.5))
        #expect(tripled == "6 servings")
        #expect(RecipeDisplay.yieldText(recipe, options: .written) != nil)
        var bare = RecipeDocument(id: "b", createdAt: 0, modifiedAt: 0)
        bare.yieldAmount = nil
        #expect(RecipeDisplay.yieldText(bare, options: .written) == nil)
    }

    // MARK: Unit conversion

    @Test func metricShowsMlAndGrams() {
        let cups = RecipeDisplay.line(line("2 cups water"), options: .init(system: .metric))
        #expect(cups.text.contains("ml"))
        #expect(cups.converted)
        let pounds = RecipeDisplay.line(line("1 lb chicken"), options: .init(system: .metric))
        #expect(pounds.text.contains("g"))
        #expect(!pounds.text.contains("lb"))
    }

    @Test func metricAmountsRenderAsDecimals() {
        // Metric reads as a decimal number; kitchen fractions ("591 1/2
        // ml") would be out of place.
        let cups = RecipeDisplay.line(line("2 cups water"), options: .init(system: .metric))
        #expect(cups.text == "473.18 ml water")
        let pounds = RecipeDisplay.line(line("1 lb chicken"), options: .init(system: .metric))
        #expect(pounds.text == "453.59 g chicken")
        let halves = RecipeDisplay.line(
            line("2 cups water"), options: .init(factor: 1.25, system: .metric))
        #expect(halves.text == "591.47 ml water")
        // Kitchen units keep their fractions.
        let written = RecipeDisplay.line(
            line("2 cups water"), options: .init(factor: 1.25))
        #expect(written.text == "2 1/2 cups water")
    }

    @Test func countLinesPassThroughConversion() {
        let eggs = RecipeDisplay.line(line("2 eggs"), options: .init(system: .metric))
        #expect(!eggs.converted)
        #expect(eggs.text == "2 eggs")
    }

    @Test func writtenSystemNeverConverts() {
        let rendered = RecipeDisplay.line(line("2 cups water"), options: .written)
        #expect(!rendered.converted)
        #expect(rendered.text == "2 cups water")
    }

    @Test func scaleThenConvertCompose() {
        // 1.5 x of 2 cups of water, to metric: 3 cups → 710 ml (rounded 2
        // decimals), not a double conversion of the stored line.
        let rendered = RecipeDisplay.line(
            line("2 cups water"), options: .init(factor: 1.5, system: .metric))
        #expect(rendered.converted)
        #expect(rendered.text.contains("ml"))
    }

    // MARK: Sections and steps

    @Test func sectionsRenderWithTheirNames() {
        let rendered = RecipeDisplay.sections(
            [
                section(["1 cup oats"], name: "Base"),
                section(["2 tbsp honey"], name: "Topping"),
            ],
            options: .written)
        #expect(rendered.count == 2)
        #expect(rendered[0].name == "Base")
        #expect(rendered[1].lines[0].text == "2 tbsp honey")
    }

    @Test func stepTextStaysWrittenAtFactorOne() {
        let step = Step(text: "Stir in 2 cups of the flour, then simmer 20 minutes.")
        let shown = RecipeDisplay.stepText(step, lines: [line("2 cups flour")], options: .written)
        #expect(shown == step.text)
    }

    @Test func stepTextSubstitutesScaledAmounts() {
        let step = Step(text: "Stir in 2 cups of the flour.")
        let shown = RecipeDisplay.stepText(
            step, lines: [line("2 cups flour")], options: .init(factor: 2))
        #expect(shown.contains("4 cups"))
        #expect(!shown.contains("2 cups"))
    }

    @Test func stepTextWithScaledOptionsMatchesPlainCall() throws {
        let step = Step(text: "Whisk in 1 cup cream and simmer 30 minutes.")
        let options = RecipeDisplay.Options(factor: 2)
        #expect(
            RecipeDisplay.stepText(step, lines: [line("1 cup heavy cream")], options: options)
                == (try RecipeMath.stepText(
                    step.text, lines: [line("1 cup heavy cream")], by: 2)))
    }

    // MARK: Unit labels

    @Test func unitLabelsPluralizeByAmount() {
        #expect(RecipeDisplay.unitLabel("cup", amount: 1) == "cup")
        #expect(RecipeDisplay.unitLabel("cup", amount: 2) == "cups")
        #expect(RecipeDisplay.unitLabel("lb", amount: 1) == "lb")
        #expect(RecipeDisplay.unitLabel("lb", amount: 2) == "lbs")
        #expect(RecipeDisplay.unitLabel("g", amount: 500) == "g")
        #expect(RecipeDisplay.unitLabel("custom", amount: 3) == "custom")
    }

    @Test func systemsHaveLabels() {
        #expect(RecipeDisplay.UnitSystem.allCases.count == 3)
        #expect(RecipeDisplay.UnitSystem.written.label == "As written")
    }
}
