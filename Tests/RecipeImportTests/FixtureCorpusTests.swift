import Foundation
import RecipeCore
import Testing

@testable import RecipeImport

/// M3.4: the reduced, rewritten page corpus. Every fixture is an
/// original reduced page written for this project; the suite imports
/// each one offline and asserts the fields the page is shaped to
/// carry. Fixtures live in Fixtures/ and are declared resources in
/// Package.swift, so `swift test` and CI both run them offline.
struct FixtureCorpusTests {
    private let now: Int64 = 1_800_000_000

    private func fixture(_ name: String) throws -> String {
        let url = Bundle.module.url(
            forResource: name, withExtension: "html", subdirectory: "Fixtures")
        return try String(contentsOf: try #require(url), encoding: .utf8)
    }

    private func extract(_ name: String) throws -> RecipeExtractor.Report {
        try #require(
            RecipeExtractor.extract(
                fromHTML: try fixture(name), now: now, id: name),
            "\(name) produced no recipe")
    }

    // MARK: JSON-LD

    @Test func f01_jsonLdFull() throws {
        let r = try extract("f01-jsonld-full")
        #expect(r.source == .jsonLd)
        #expect(r.document.title == "Lentil Soup")
        #expect(r.document.summary == "A weeknight soup with carrots and lentils.")
        #expect(r.document.yieldAmount == 4)
        #expect(r.document.prepTime == .minutes(15))
        #expect(r.document.cookTime == .minutes(40))
        #expect(r.document.totalTime == .minutes(55))
        #expect(r.document.ingredientSections[0].lines.count == 4)
        #expect(r.document.stepSections[0].steps.count == 3)
        #expect(r.document.categories == ["Soup"])
        #expect(r.document.cuisine == "Mediterranean")
        #expect(r.document.tags.contains("weeknight"))
        #expect(r.document.nutrition["calories"] == "320 kcal")
        #expect(r.document.nutrition["proteinContent"] == "18 g")
        #expect(r.document.attribution == "Example Kitchen")
    }

    @Test func f02_jsonLdHowToSections() throws {
        let r = try extract("f02-jsonld-howtosections")
        #expect(r.document.title == "Buttermilk Pancakes")
        #expect(r.document.yieldAmount == 12)
        #expect(r.document.yieldUnit == "pancakes")
        let sections = r.document.stepSections
        #expect(sections.count == 2)
        #expect(sections[0].name == "Batter")
        #expect(sections[1].name == "Cook")
        #expect(sections[0].steps.count == 2)
        #expect(sections[1].steps.count == 2)
    }

    @Test func f03_jsonLdStepObjects() throws {
        let r = try extract("f03-jsonld-step-objects")
        #expect(r.document.title == "Tomato Sauce")
        #expect(r.document.yieldAmount == 1)
        #expect(r.document.yieldUnit == "quart")
        #expect(r.document.prepTime == .minutes(10))
        #expect(r.document.cookTime == .hours(2))
        let steps = r.document.stepSections[0].steps
        #expect(steps.count == 3)
        #expect(steps[0].text == "Crush the tomatoes.")
    }

    @Test func f04_jsonLdGraph() throws {
        let r = try extract("f04-jsonld-graph")
        #expect(r.document.title == "Pickled Beets")
        #expect(r.document.yieldAmount == 2)
        #expect(r.document.ingredientSections[0].lines.count == 3)
    }

    @Test func f05_jsonLdDurations() throws {
        let r = try extract("f05-jsonld-durations")
        #expect(r.document.totalTime == RecipeCore.Duration(seconds: 26 * 3600))
        #expect(r.document.prepTime == RecipeCore.Duration(seconds: 3600 + 15 * 60 + 10))
        #expect(r.document.cookTime == RecipeCore.Duration(seconds: 2 * 3600))
    }

    @Test func f06_jsonLdYieldCookies() throws {
        let r = try extract("f06-jsonld-yield-cookies")
        #expect(r.document.yieldAmount == 24)
        #expect(r.document.yieldUnit == "cookies")
    }

    @Test func f07_jsonLdNutrition() throws {
        let r = try extract("f07-jsonld-nutrition")
        let n = r.document.nutrition
        #expect(n["calories"] == "450 kcal")
        #expect(n["proteinContent"] == "28 g")
        #expect(n["sodiumContent"] == "380 mg")
        #expect(n["servingSize"] == "1 bowl")
        #expect(n["transFatContent"] == "0 g")
        #expect(n.count == 12)
    }

    @Test func f08_jsonLdAuthorOrg() throws {
        let r = try extract("f08-jsonld-author-org")
        #expect(r.document.attribution == "Example Test Kitchen")
        #expect(r.document.yieldAmount == 0.75)
        #expect(r.document.yieldUnit == "cup")
    }

    @Test func f09_jsonLdItemListFallsBack() throws {
        // The page has no Recipe JSON-LD; the heuristic body must win.
        let r = try extract("f09-jsonld-itemlist-falls-back")
        #expect(r.source == .heuristic)
        #expect(r.document.title == "Cold Brew")
    }

    @Test func f10_jsonLdEscapes() throws {
        let r = try extract("f10-jsonld-escapes")
        #expect(r.document.title == "Fish & Chips")
        #expect(r.document.summary == "Fry — in batches — until golden.")
        let steps = r.document.stepSections[0].steps
        #expect(steps[1].text.contains("Fry — 6 minutes per batch."))
    }

    // MARK: Microdata

    @Test func f11_microdataFull() throws {
        let r = try extract("f11-microdata-full")
        #expect(r.source == .microdata)
        #expect(r.document.title == "Root Vegetable Stew")
        #expect(r.document.summary == "A slow stew of roots and beans.")
        #expect(r.document.yieldAmount == 6)
        #expect(r.document.prepTime == .minutes(20))
        #expect(r.document.cookTime == .hours(1))
        #expect(r.document.totalTime == RecipeCore.Duration(seconds: 3600 + 20 * 60))
        #expect(r.document.ingredientSections[0].lines.count == 3)
        #expect(r.document.stepSections[0].steps.count == 3)
        #expect(r.document.categories == ["Stew"])
        #expect(r.document.cuisine == "American")
        #expect(r.document.tags.contains("vegan"))
        #expect(r.document.nutrition["calories"] == "410 kcal")
        #expect(r.document.attribution == "Example Cook")
    }

    @Test func f12_microdataIngredientStubs() throws {
        let r = try extract("f12-microdata-ingredient-stubs")
        #expect(r.document.title == "Lasagna")
        #expect(r.document.yieldAmount == 8)
        #expect(r.document.ingredientSections[0].lines.count == 4)
        #expect(r.document.stepSections[0].steps.count == 3)
    }

    @Test func f13_microdataNestedDuration() throws {
        let r = try extract("f13-microdata-nested-duration")
        #expect(r.document.title == "Braised Short Ribs")
        #expect(r.document.totalTime == RecipeCore.Duration(seconds: 3 * 3600 + 30 * 60))
    }

    @Test func f14_microdataHowToSections() throws {
        let r = try extract("f14-microdata-howtosections")
        #expect(r.document.title == "Dumplings")
        let sections = r.document.stepSections
        #expect(sections.count == 2)
        #expect(sections[0].name == "Filling")
        #expect(sections[1].name == "Wrap")
        #expect(sections[0].steps.count == 2)
    }

    @Test func f15_microdataMinimal() throws {
        let r = try extract("f15-microdata-minimal")
        #expect(r.document.title == "Boiled Eggs")
        #expect(r.document.yieldAmount == nil)
        #expect(r.document.ingredientSections[0].lines.count == 1)
    }

    @Test func f16_microdataImages() throws {
        let r = try extract("f16-microdata-images")
        #expect(r.document.title == "Berry Tart")
        #expect(r.document.yieldAmount == 1)
        #expect(r.document.yieldUnit == "tart")
    }

    // MARK: Heuristic

    @Test func f17_heuristicLists() throws {
        let r = try extract("f17-heuristic-lists")
        #expect(r.source == .heuristic)
        #expect(r.document.title == "Weeknight Curry")
        #expect(r.document.yieldAmount == 4)
        #expect(r.document.prepTime == .minutes(15))
        #expect(r.document.cookTime == .minutes(30))
        #expect(r.document.ingredientSections[0].lines.count == 4)
        #expect(r.document.stepSections[0].steps.count == 4)
    }

    @Test func f18_heuristicParagraphs() throws {
        let r = try extract("f18-heuristic-paragraphs")
        #expect(r.document.title == "Grilled Cheese")
        #expect(r.document.ingredientSections[0].lines.count == 3)
        #expect(r.document.stepSections[0].steps.count == 2)
    }

    @Test func f19_heuristicMetaLine() throws {
        let r = try extract("f19-heuristic-meta-line")
        #expect(r.document.title == "Roast Chicken")
        #expect(r.document.yieldAmount == 4)
        #expect(r.document.prepTime == .minutes(20))
        #expect(r.document.cookTime == RecipeCore.Duration(seconds: 3600 + 15 * 60))
    }

    @Test func f20_heuristicDivs() throws {
        let r = try extract("f20-heuristic-divs")
        #expect(r.document.title == "Mushroom Barley Soup")
        #expect(r.document.yieldAmount == 6)
        #expect(r.document.yieldUnit == "bowls")
        #expect(r.document.ingredientSections[0].lines.count == 3)
        #expect(r.document.stepSections[0].steps.count == 3)
    }

    @Test func f21_heuristicNoYield() throws {
        let r = try extract("f21-heuristic-no-yield")
        #expect(r.document.title == "Cucumber Salad")
        #expect(r.document.yieldAmount == nil)
        #expect(r.document.ingredientSections[0].lines.count == 3)
    }

    @Test func f22_notRecipe() throws {
        #expect(
            RecipeExtractor.extract(
                fromHTML: try fixture("f22-not-recipe"), now: now,
                id: "f22") == nil)
    }

    @Test func f23_brokenJsonLdFallsBack() throws {
        let r = try extract("f23-broken-jsonld-falls-back")
        #expect(r.source == .microdata)
        #expect(r.document.title == "Recovery Stew")
        #expect(r.document.ingredientSections[0].lines.count == 2)
    }

    @Test func f24_emptyPage() throws {
        #expect(
            RecipeExtractor.extract(
                fromHTML: try fixture("f24-empty-page"), now: now,
                id: "f24") == nil)
    }

    // MARK: Edge shapes

    @Test func f25_yieldNumberOnly() throws {
        let r = try extract("f25-yield-number-only")
        #expect(r.document.yieldAmount == 4)
        #expect(r.document.yieldUnit == "servings")
    }

    @Test func f26_nameFromTitle() throws {
        let r = try extract("f26-name-from-title")
        #expect(r.document.title == "Pesto Pasta")
        #expect(r.document.yieldAmount == 6)
    }

    @Test func f27_ingredientEntities() throws {
        let r = try extract("f27-ingredient-entities")
        let lines = r.document.ingredientSections[0].lines
        #expect(lines.count == 3)
        #expect(lines[0].originalText.contains("cored & diced"))
        #expect(lines[1].originalText.contains("½ cup water"))
        #expect(lines[2].originalText.contains("fresh"))
        #expect(!lines[2].originalText.contains("<i>"))
    }

    @Test func f28_categoryCuisineKeywords() throws {
        let r = try extract("f28-category-cuisine-keywords")
        #expect(r.document.categories == ["Main course"])
        #expect(r.document.cuisine == "Korean")
        #expect(r.document.tags == ["rice", "vegetables", "egg"])
    }

    @Test func f29_stepNames() throws {
        let r = try extract("f29-step-names")
        #expect(r.document.stepSections[0].steps.count == 3)
        #expect(r.document.stepSections[0].steps[0].text == "Boil sugar and water.")
    }

    @Test func f30_twoRecipesFirstWins() throws {
        let r = try extract("f30-two-recipes")
        #expect(r.document.title == "First Pancake")
        #expect(r.document.yieldAmount == 4)
    }

    @Test func f31_sourceURL() throws {
        let r = try extract("f31-source-url")
        #expect(r.document.sourceURL == "https://recipes.example.com/chili")
    }

    @Test func f32_malformedDuration() throws {
        let r = try extract("f32-malformed-duration")
        #expect(r.document.prepTime == nil)
        #expect(r.document.cookTime == .minutes(45))
    }

    @Test func f33_microdataAuthorDate() throws {
        let r = try extract("f33-microdata-author-date")
        #expect(r.document.attribution == "A Neighbor")
        #expect(r.document.title == "Rhubarb Crisp")
    }

    @Test func f34_heuristicServingsPhrase() throws {
        let r = try extract("f34-heuristic-servings-phrase")
        #expect(r.document.yieldAmount == 6)
    }

    @Test func f35_stepDurations() throws {
        let r = try extract("f35-step-durations")
        let steps = r.document.stepSections[0].steps
        #expect(steps[0].text.contains("Simmer the rice in milk 35 minutes."))
    }

    @Test func f36_jsonScriptType() throws {
        let r = try extract("f36-json-script")
        #expect(r.document.title == "Cold Noodles")
        #expect(r.document.ingredientSections[0].lines.count == 2)
    }

    @Test func f37_heuristicFrenchHeaders() throws {
        let r = try extract("f37-heuristic-french-headers")
        #expect(r.document.title == "Coq au Vin")
        #expect(r.document.yieldAmount == 6)
        #expect(r.document.cookTime == RecipeCore.Duration(seconds: 2 * 3600 + 30 * 60))
    }

    @Test func f38_yieldRange() throws {
        let r = try extract("f38-yield-range")
        #expect(r.document.yieldAmount == 24)
        #expect(r.document.yieldUnit == "meatballs")
    }

    @Test func f39_heuristicPipeMeta() throws {
        let r = try extract("f39-heuristic-pipe-meta")
        #expect(r.document.title == "One-Pot Chicken and Rice")
        #expect(r.document.yieldAmount == 4)
        #expect(r.document.prepTime == .minutes(10))
        #expect(r.document.totalTime == .minutes(45))
    }

    @Test func f40_nestedGraph() throws {
        let r = try extract("f40-nested-graph")
        #expect(r.document.title == "Smoked Trout Dip")
        #expect(r.document.yieldAmount == 2)
    }

    @Test func f41_emptyJsonLdRecipe() throws {
        // The empty Recipe JSON-LD can't make a document; heuristic wins.
        let r = try extract("f41-empty-jsonld-recipe")
        #expect(r.source == .heuristic)
        #expect(r.document.title == "Orphan Curry")
    }

    @Test func f42_whitespaceValues() throws {
        let r = try extract("f42-whitespace-values")
        #expect(r.document.title == "Miso Soup")
        #expect(r.document.yieldAmount == 4)
        let lines = r.document.ingredientSections[0].lines
        #expect(lines[0].originalText == "4 cups dashi")
    }

    @Test func f43_categoryCuisineHeuristic() throws {
        let r = try extract("f43-category-cuisine-heuristic")
        #expect(r.document.categories.contains("Breakfast"))
        #expect(r.document.cuisine == "Middle Eastern")
        #expect(r.document.yieldAmount == 4)
    }

    @Test func f44_upperName() throws {
        let r = try extract("f44-upper-name")
        #expect(r.document.title == "Banana Bread")
    }

    @Test func f45_yieldVerbose() throws {
        let r = try extract("f45-yield-verbose")
        #expect(r.document.yieldAmount == 12)
        #expect(r.document.yieldUnit == "scones")
    }

    @Test func f46_fractionChars() throws {
        let r = try extract("f46-fraction-chars")
        let lines = r.document.ingredientSections[0].lines
        #expect(lines[0].quantity?.amount == 1.5)
        #expect(lines[2].quantity?.amount == Decimal(2) / Decimal(3))
    }

    @Test func f47_longDescription() throws {
        let r = try extract("f47-long-description")
        #expect(r.document.summary.hasPrefix("This braised beef taco"))
        #expect(r.document.yieldAmount == 12)
        #expect(r.document.yieldUnit == "tacos")
    }

    @Test func f48_videoObject() throws {
        let r = try extract("f48-video-object")
        #expect(r.document.title == "Sheet Pan Fajitas")
        #expect(r.document.ingredientSections[0].lines.count == 3)
    }

    @Test func f49_aggregateRating() throws {
        let r = try extract("f49-aggregate-rating")
        #expect(r.document.title == "Miso Glazed Salmon")
        #expect(r.document.rating == 0)
    }

    @Test func f50_zeroIngredients() throws {
        let r = try extract("f50-zero-ingredients")
        #expect(r.document.title == "Ice Water")
        #expect(r.document.ingredientSections.isEmpty)
        #expect(r.document.stepSections[0].steps.count == 2)
    }

    @Test func f51_yieldDoubleHint() throws {
        let r = try extract("f51-yield-double-hint")
        #expect(r.document.yieldAmount == 3)
        #expect(r.document.yieldUnit == "cups")
    }

    @Test func f52_notesField() throws {
        let r = try extract("f52-notes-field")
        #expect(r.document.notes.contains("taller puff"))
    }

    @Test func f53_urlWithQuery() throws {
        let r = try extract("f53-url-with-query")
        #expect(
            r.document.sourceURL == "https://recipes.example.com/falafel?utm=share")
    }

    @Test func f54_scriptTypeFiltering() throws {
        let r = try extract("f54-script-type-filtering")
        #expect(r.document.title == "Udon")
        #expect(r.document.ingredientSections[0].lines.count == 2)
    }

    @Test func f55_partialNutrition() throws {
        let r = try extract("f55-partial-nutrition")
        #expect(r.document.nutrition["calories"] == "120 kcal")
        #expect(r.document.nutrition["sugarContent"] == "8 g")
        #expect(r.document.nutrition["proteinContent"] == nil)
    }

    @Test func f56_microdataYieldRange() throws {
        let r = try extract("f56-microdata-yield-range")
        #expect(r.document.yieldAmount == 12)
        #expect(r.document.yieldUnit == "rolls")
    }

    @Test func f57_heuristicNumberedDivs() throws {
        let r = try extract("f57-heuristic-numbered-divs")
        #expect(r.document.title == "Tomato Sandwich")
        #expect(r.document.yieldAmount == 2)
        #expect(r.document.ingredientSections[0].lines.count == 3)
        #expect(r.document.stepSections[0].steps.count == 2)
    }

    @Test func f58_ingredientsOnly() throws {
        let r = try extract("f58-ingredients-only")
        #expect(r.document.title == "Simple Syrup")
        #expect(r.document.ingredientSections[0].lines.count == 2)
        #expect(r.document.stepSections.isEmpty)
    }

    @Test func f59_authorString() throws {
        let r = try extract("f59-author-string")
        #expect(r.document.attribution == "Cocoa Fan")
        #expect(r.document.yieldAmount == 2)
        #expect(r.document.yieldUnit == "mugs")
    }

    @Test func f60_faqWithRecipe() throws {
        let r = try extract("f60-faq-with-recipe")
        #expect(r.document.title == "Basil Pesto")
        #expect(r.document.ingredientSections[0].lines.count == 2)
    }

    @Test func f61_microdataArticle() throws {
        let r = try extract("f61-microdata-article")
        #expect(r.source == .microdata)
        #expect(r.document.title == "Panzanella")
        #expect(r.document.yieldAmount == 4)
    }

    @Test func f62_instructionsString() throws {
        let r = try extract("f62-instructions-string")
        let steps = r.document.stepSections[0].steps
        #expect(steps.count == 2)
        #expect(steps[0].text == "Steam 8 minutes.")
    }

    @Test func f63_heuristicYieldLabel() throws {
        let r = try extract("f63-heuristic-yield-label")
        #expect(r.document.title == "Stovetop Mac and Cheese")
        #expect(r.document.yieldAmount == 6)
        #expect(r.document.totalTime == .minutes(25))
    }

    @Test func f64_singleIngredientString() throws {
        let r = try extract("f64-single-ingredient-string")
        #expect(r.document.ingredientSections[0].lines.count == 1)
        #expect(r.document.ingredientSections[0].lines[0].item == "heavy cream")
    }

    @Test func f65_keywordsArray() throws {
        let r = try extract("f65-keywords-array")
        #expect(r.document.tags == ["chickpeas", "dip", "middle eastern"])
    }

    @Test func f66_microdataDuplicateNames() throws {
        let r = try extract("f66-microdata-duplicate-names")
        #expect(r.document.title == "Trust Me Soup")
        #expect(r.document.yieldAmount == 3)
    }

    @Test func f67_microdataCaseInsensitive() throws {
        let r = try extract("f67-microdata-case-insensitive")
        #expect(r.source == .microdata)
        #expect(r.document.title == "Miso Butter Noodles")
        #expect(r.document.ingredientSections[0].lines.count == 2)
        #expect(r.document.stepSections[0].steps.count == 2)
    }

    @Test func f68_heuristicDuplicates() throws {
        let r = try extract("f68-heuristic-duplicates")
        let lines = r.document.ingredientSections[0].lines
        #expect(lines.count == 3)
        #expect(lines[0].originalText == "2 cups almonds")
    }

    @Test func f69_notesAndTips() throws {
        let r = try extract("f69-notes-and-tips")
        #expect(r.document.notes.contains("reduced syrup"))
        #expect(r.document.notes.contains("Bosc"))
    }

    @Test func f70_yieldServingNoun() throws {
        let r = try extract("f70-yield-serving-noun")
        #expect(r.document.yieldAmount == 4)
        #expect(r.document.yieldUnit == "servings")
    }
}
