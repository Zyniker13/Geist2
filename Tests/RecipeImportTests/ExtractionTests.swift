import Foundation
import RecipeCore
import Testing

@testable import RecipeImport

/// ISO 8601 durations, in full.
struct ISODurationTests {
    @Test func parsesBasicDurations() {
        #expect(ISODuration.parse("PT30M") == 1_800)
        #expect(ISODuration.parse("PT1H") == 3_600)
        #expect(ISODuration.parse("PT1H30M") == 5_400)
        #expect(ISODuration.parse("PT45M") == 2_700)
        #expect(ISODuration.parse("P0D") == 0)
        #expect(ISODuration.parse("P1D") == 86_400)
        #expect(ISODuration.parse("PT1H15M10S") == 4_510)
    }

    @Test func parsesCompoundAndDateTimeForms() {
        #expect(ISODuration.parse("P1DT1H") == 90_000)
        #expect(ISODuration.parse("P2DT3H30M") == 185_400)
        #expect(ISODuration.parse("P1W") == 604_800)
        #expect(ISODuration.parse("PT0S") == 0)
        #expect(ISODuration.parse("PT0H0M10S") == 10)
    }

    @Test func rejectsMalformed() {
        #expect(ISODuration.parse("") == nil)
        #expect(ISODuration.parse("45 minutes") == nil)
        #expect(ISODuration.parse("PT") == nil)
        #expect(ISODuration.parse("PTX") == nil)
        #expect(ISODuration.parse("PT1H30") == nil)  // trailing number
        #expect(ISODuration.parse("1H30M") == nil)  // no P
        #expect(ISODuration.parse("PTTT") == nil)
    }

    @Test func rendersShortestForm() {
        #expect(ISODuration.render(seconds: 5_400) == "PT1H30M")
        #expect(ISODuration.render(seconds: 3_600) == "PT1H")
        #expect(ISODuration.render(seconds: 1_800) == "PT30M")
        #expect(ISODuration.render(seconds: 0) == "PT0S")
        #expect(ISODuration.render(seconds: 86_400) == "P1D")
        #expect(ISODuration.render(seconds: 4_510) == "PT1H15M10S")
    }

    @Test func roundTrips() {
        for seconds in [1, 59, 60, 61, 3_599, 3_600, 86_400, 187_800] {
            #expect(ISODuration.parse(ISODuration.render(seconds: seconds)) == seconds)
        }
    }

    @Test func display() {
        #expect(durationDisplay(seconds: 5_400) == "1 hr 30 mins")
        #expect(durationDisplay(seconds: 0) == "")
        #expect(durationDisplay(seconds: 45) == "45 secs")
    }
}

/// JSON-LD extraction over reduced fixture pages.
struct JSONLDExtractorTests {
    @Test func extractsCompleteRecipe() throws {
        let html = """
            <html><head>
            <script type="application/ld+json">
            {"@context":"https://schema.org","@type":"Recipe",
             "name":"Test Soup","description":"A warm soup",
             "recipeYield":"4 servings","recipeCategory":"Soups",
             "recipeCuisine":"American","keywords":"soup,easy",
             "author":{"@type":"Person","name":"Test Author"},
             "prepTime":"PT15M","cookTime":"PT30M","totalTime":"PT45M",
             "recipeIngredient":["2 tbsp olive oil","1 onion, chopped"],
             "recipeInstructions":[
               {"@type":"HowToStep","text":"Heat the oil."},
               {"@type":"HowToStep","text":"Soften the onion."}],
             "image":["https://example.com/soup.jpg"],
             "nutrition":{"calories":"210 kcal","proteinContent":"6 g"}}
            </script>
            </head><body>irrelevant</body></html>
            """
        let recipe = try #require(JSONLDExtractor.extract(from: html))
        #expect(recipe.name == "Test Soup")
        #expect(recipe.description == "A warm soup")
        #expect(recipe.recipeYield == "4 servings")
        #expect(recipe.author == "Test Author")
        #expect(recipe.prepTime == "PT15M")
        #expect(recipe.ingredients.count == 2)
        #expect(recipe.instructions.count == 2)
        #expect(recipe.images == ["https://example.com/soup.jpg"])
        #expect(recipe.nutrition["calories"] == "210 kcal")
    }

    @Test func findsRecipeInsideGraphAndArrays() throws {
        let html = """
            <script type="application/ld+json">
            {"@context":"https://schema.org","@graph":[
              {"@type":"WebPage","name":"Page"},
              {"@type":"Recipe","name":"Graph Soup",
               "recipeIngredient":["1 cup rice"]}]}
            </script>
            """
        let recipe = try #require(JSONLDExtractor.extract(from: html))
        #expect(recipe.name == "Graph Soup")
        #expect(recipe.ingredients == ["1 cup rice"])
    }

    @Test func howToSectionsKeepNamesAndOrder() throws {
        let html = """
            <script type="application/ld+json">
            {"@type":"Recipe","name":"Layered Dish",
             "recipeInstructions":[
              {"@type":"HowToSection","name":"Make the base",
               "itemListElement":[
                 {"@type":"HowToStep","text":"Mix the flour."},
                 {"@type":"HowToStep","text":"Add water."}]},
              {"@type":"HowToSection","name":"Finish",
               "itemListElement":[{"@type":"HowToStep","text":"Bake it."}]}]}
            </script>
            """
        let recipe = try #require(JSONLDExtractor.extract(from: html))
        #expect(recipe.instructionSections.count == 2)
        #expect(recipe.instructionSections[0].name == "Make the base")
        #expect(recipe.instructionSections[0].steps == ["Mix the flour.", "Add water."])
        #expect(recipe.instructionSections[1].steps == ["Bake it."])
    }

    @Test func plainStringInstructionsAndYield() throws {
        let html = """
            <script type="application/ld+json">
            {"@type":"Recipe","name":"Simple","recipeYield":"2 dozen",
             "recipeIngredient":["2 cups flour"],
             "recipeInstructions":["Stir.","Knead 10 minutes."]}
            </script>
            """
        let recipe = try #require(JSONLDExtractor.extract(from: html))
        #expect(recipe.instructions == ["Stir.", "Knead 10 minutes."])
        #expect(recipe.recipeYield == "2 dozen")
    }

    @Test func unescapesEntitiesInsideJSON() throws {
        let html = """
            <script type="application/ld+json">
            {"@type":"Recipe","name":"Bennys &amp; Jerrys Chili",
             "recipeInstructions":["Simmer 5 &lt;em&gt;hours&lt;/em&gt;."]}
            </script>
            """
        let recipe = try #require(JSONLDExtractor.extract(from: html))
        #expect(recipe.name == "Bennys & Jerrys Chili")
        #expect(recipe.instructions == ["Simmer 5 <em>hours</em>."])
    }

    @Test func nonRecipeJSONReturnsNil() {
        let html = """
            <script type="application/ld+json">
            {"@type":"Organization","name":"Example Co"}
            </script>
            """
        #expect(JSONLDExtractor.extract(from: html) == nil)
    }
}

/// The extracted block becomes a RecipeDocument.
struct RecipeAssemblerTests {
    @Test func assemblesDocument() throws {
        let recipe = JSONLDRecipe(
            name: "Test Stew", description: "Hearty",
            recipeYield: "4 servings", recipeCategory: "Mains",
            recipeCuisine: "French", keywords: "stew, winter",
            author: "Alice", prepTime: "PT20M", cookTime: "PT1H",
            ingredients: [
                "2 tbsp olive oil", "1 onion, chopped", "salt to taste",
            ],
            instructions: ["Brown the onion.", "Simmer 1 hour."],
            images: ["https://example.com/stew.jpg"],
            nutrition: ["calories": "300 kcal"])
        let document = try #require(
            RecipeAssembler.document(from: recipe, now: 1_000, id: "test-id"))
        #expect(document.title == "Test Stew")
        #expect(document.summary == "Hearty")
        #expect(document.yieldAmount == 4)
        #expect(document.yieldUnit == "servings")
        #expect(document.prepTime?.seconds == 1_200)
        #expect(document.cookTime?.seconds == 3_600)
        #expect(document.cuisine == "French")
        #expect(document.tags == ["stew", "winter"])
        #expect(document.attribution == "Alice")
        #expect(document.nutrition["calories"] == "300 kcal")
        // The M2 parser handled the ingredient lines.
        #expect(document.ingredientSections[0].lines[0].quantity?.amount == 2)
        #expect(document.ingredientSections[0].lines[0].unitID == "tbsp")
        #expect(document.ingredientSections[0].lines[1].preparation == "chopped")
        #expect(document.ingredientSections[0].lines[2].toTaste)
        #expect(document.stepSections[0].steps.count == 2)
        // "Simmer 1 hour" carries a timer.
        #expect(document.stepSections[0].steps[1].timers == [RecipeCore.Duration(seconds: 3_600)])
    }

    @Test func howToSectionsKeepTheirNames() {
        let recipe = JSONLDRecipe(
            name: "Sections", ingredients: [],
            instructionSections: [
                ("First", ["Do a.", "Do b."]), ("Second", ["Do c."]),
            ])
        let document = RecipeAssembler.document(
            from: recipe, now: 0, id: "x")
        let sections = document?.stepSections ?? []
        #expect(sections.map(\.name) == ["First", "Second"])
        #expect(sections.map { $0.steps.map(\.text) } == [["Do a.", "Do b."], ["Do c."]])
    }

    @Test func yieldForms() {
        var document = RecipeDocument(id: "y", title: "", createdAt: 0, modifiedAt: 0)
        RecipeAssembler.applyYield("4 servings", to: &document)
        #expect(document.yieldAmount == 4)
        #expect(document.yieldUnit == "servings")
        RecipeAssembler.applyYield("2 dozen cookies", to: &document)
        #expect(document.yieldAmount == 2)
        #expect(document.yieldUnit == "dozen cookies")
        RecipeAssembler.applyYield("Serves 6", to: &document)
        #expect(document.yieldAmount == 6)
        RecipeAssembler.applyYield("One 9-inch pie", to: &document)
        #expect(document.yieldUnit == "One 9-inch pie")
    }

    @Test func emptyBlockProducesNil() {
        let recipe = JSONLDRecipe(name: "", ingredients: [], instructions: [])
        #expect(RecipeAssembler.document(from: recipe, now: 0, id: "x") == nil)
    }
}
