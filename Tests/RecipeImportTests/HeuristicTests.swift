import Foundation
import RecipeCore
import Testing

@testable import RecipeImport

/// The last-resort extractor for pages without structured data.
struct HeuristicExtractorTests {
    @Test func findsTitleIngredientsAndSteps() throws {
        let html = """
            <html><head><title>Test Pancakes</title></head><body>
            <h1>Pantry Pancakes</h1>
            <p>Simple pancakes from what's in the pantry.</p>
            <p>Serves 4</p>
            <h2>Ingredients</h2>
            <ul>
            <li>2 cups flour</li>
            <li>1 tbsp sugar</li>
            <li>1 tsp salt</li>
            </ul>
            <h2>Directions</h2>
            <ol>
            <li>Whisk the dry ingredients.</li>
            <li>Add the milk and stir until smooth.</li>
            <li>Pour onto a hot griddle.</li>
            </ol>
            </body></html>
            """
        let recipe = try #require(HeuristicExtractor.extract(from: html))
        #expect(recipe.name == "Pantry Pancakes")
        #expect(recipe.description == "Simple pancakes from what's in the pantry.")
        #expect(recipe.recipeYield == "Serves 4")
        #expect(recipe.ingredients == ["2 cups flour", "1 tbsp sugar", "1 tsp salt"])
        #expect(recipe.instructions.count == 3)
        #expect(recipe.instructions[0] == "Whisk the dry ingredients.")
    }

    @Test func extractsTimesAnywhere() throws {
        let html = """
            <div>
            <h1>Stew</h1>
            <p>Prep time: 20 minutes</p>
            <p>Cook time: 1 hour 30 minutes</p>
            <p>Total time: 1 hr 50 min</p>
            <h2>Ingredients</h2>
            <li>1 kg beef</li>
            <h2>Method</h2>
            <li>Brown the beef.</li>
            </div>
            """
        let recipe = try #require(HeuristicExtractor.extract(from: html))
        #expect(recipe.prepTime == "PT20M")
        #expect(recipe.cookTime == "PT1H30M")
        #expect(recipe.totalTime == "PT1H50M")
    }

    @Test func numberedListsBecomeSteps() throws {
        let html = """
            <h1>Roast</h1>
            <h3>Ingredients</h3>
            <p>1. one chicken</p>
            <p>2. salt</p>
            <h3>Instructions</h3>
            <p>1. Season the chicken.</p>
            <p>2. Roast at 180 degrees for 90 minutes.</p>
            """
        let recipe = try #require(HeuristicExtractor.extract(from: html))
        #expect(recipe.ingredients == ["one chicken", "salt"])
        #expect(
            recipe.instructions == ["Season the chicken.", "Roast at 180 degrees for 90 minutes."])
    }

    @Test func stepMarkersAreStripped() throws {
        let html = """
            <h1>Tea</h1>
            <p>Ingredients</p>
            <p>- 2 tsp tea leaves</p>
            <p>Steps</p>
            <p>Step 1: Boil the water.</p>
            <p>Step 2: Steep five minutes.</p>
            """
        let recipe = try #require(HeuristicExtractor.extract(from: html))
        #expect(recipe.instructions == ["Boil the water.", "Steep five minutes."])
    }

    @Test func sectionHeadingsCarryTheirSteps() throws {
        let html = """
            <h1>Lasagna</h1>
            <p>Ingredients: 1 box pasta, 2 cups cheese</p>
            <h3>Make the sauce</h3>
            <li>Simmer the tomatoes.</li>
            <li>Season with basil.</li>
            <h3>Assemble</h3>
            <li>Layer the pasta.</li>
            """
        let recipe = try #require(HeuristicExtractor.extract(from: html))
        #expect(recipe.ingredients.count == 2)
        #expect(recipe.instructionSections.count == 2)
        #expect(recipe.instructionSections[0].name == "Make the sauce")
        #expect(recipe.instructionSections[0].steps.count == 2)
        #expect(recipe.instructionSections[1].name == "Assemble")
    }

    @Test func imageUrlsComeFromImgTags() throws {
        let html = """
            <h1>Cake</h1>
            <img src="https://example.com/cake.jpg" alt="a cake">
            <img src="/relative.jpg">
            <img data-src="https://example.com/lazy.jpg">
            <p>Ingredients</p>
            <li>2 cups sugar</li>
            """
        let recipe = try #require(HeuristicExtractor.extract(from: html))
        #expect(recipe.images == ["https://example.com/cake.jpg", "https://example.com/lazy.jpg"])
    }

    @Test func ordinaryPageIsNotARecipe() {
        let html = """
            <h1>Welcome to Example News</h1>
            <p>Today in the news: nothing happened, and everyone stayed home.</p>
            <p>The weather was mild. Roads were quiet. Cookies were eaten.</p>
            <p>Read more about the mild weather at example.com/weather.</p>
            """
        #expect(HeuristicExtractor.extract(from: html) == nil)
    }

    @Test func fieldsAreMarkedForReviewByDesign() throws {
        // The extractor returns a plain JSONLDRecipe; the confidence
        // marking happens when the document is assembled. The contract
        // here: what it finds is honest, never invented.
        let html = """
            <h1>Soup</h1>
            <p>Ingredients</p>
            <li>3 carrots</li>
            <p>Directions</p>
            <li>Boil the carrots.</li>
            """
        let recipe = try #require(HeuristicExtractor.extract(from: html))
        #expect(recipe.nutrition.isEmpty)
        #expect(recipe.author == nil)
        #expect(recipe.prepTime == nil)
    }
}
