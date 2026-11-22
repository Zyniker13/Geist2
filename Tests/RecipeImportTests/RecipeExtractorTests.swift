import Foundation
import RecipeCore
import Testing

@testable import RecipeImport

/// The public extraction chain: ordered by trust, one entry point.
struct RecipeExtractorTests {
    private let now: Int64 = 1_800_000_000

    @Test func jsonLdWinsOverMicrodataAndHeuristic() throws {
        // A page that carries both: the JSON-LD result must win.
        let html = """
            <html><head>
            <script type="application/ld+json">
            {"@type":"Recipe","name":"Structured Soup",
             "recipeIngredient":["1 cup water"]}
            </script>
            </head><body>
            <div itemscope itemtype="https://schema.org/Recipe">
            <span itemprop="name">Microdata Soup</span>
            </div>
            </body></html>
            """
        let report = try #require(
            RecipeExtractor.extract(fromHTML: html, now: now, id: "r1"))
        #expect(report.source == .jsonLd)
        #expect(report.document.title == "Structured Soup")
    }

    @Test func microdataWinsWhenNoJsonLd() throws {
        let html = """
            <div itemscope itemtype="https://schema.org/Recipe">
            <span itemprop="name">Microdata Stew</span>
            <span itemprop="recipeIngredient">2 cups lentils</span>
            </div>
            """
        let report = try #require(
            RecipeExtractor.extract(fromHTML: html, now: now, id: "r2"))
        #expect(report.source == .microdata)
        #expect(report.document.title == "Microdata Stew")
    }

    @Test func heuristicCatchesPlainMarkup() throws {
        let html = """
            <h1>Toast</h1>
            <p>Ingredients</p>
            <p>2 slices bread</p>
            <p>Directions</p>
            <p>Toast the bread.</p>
            """
        let report = try #require(
            RecipeExtractor.extract(fromHTML: html, now: now, id: "r3"))
        #expect(report.source == .heuristic)
        #expect(report.document.title == "Toast")
    }

    @Test func nothingRecipeShapedReturnsNil() {
        let html = "<h1>About Us</h1><p>We sell shoes. Visit our store.</p>"
        #expect(
            RecipeExtractor.extract(fromHTML: html, now: now, id: "r4") == nil)
    }

    @Test func pastedTextParsesThroughTheChain() throws {
        let text = """
            Grandma's Oatmeal Cookies
            Makes 24 cookies

            Ingredients
            - 2 cups oats
            - 1 cup flour
            - 1 tsp cinnamon

            Directions
            1. Mix the dry ingredients.
            2. Add the butter and blend.
            """
        let report = try #require(
            RecipeExtractor.extract(fromText: text, now: now, id: "r5"))
        #expect(report.source == .heuristic)
        #expect(report.document.title == "Grandma's Oatmeal Cookies")
        #expect(report.document.ingredientSections.count == 1)
        #expect(report.document.ingredientSections[0].lines.count == 3)
        #expect(report.document.stepSections.count == 1)
        #expect(report.document.stepSections[0].steps.count == 2)
    }

    @Test func extractedFieldsParseWithTheM2Parser() throws {
        let html = """
            <h1>Pilaf</h1>
            <p>Ingredients</p>
            <p>500 g rice</p>
            <p>Directions</p>
            <p>Simmer 20 minutes.</p>
            """
        let report = try #require(
            RecipeExtractor.extract(fromHTML: html, now: now, id: "r6"))
        let row = try #require(report.document.ingredientSections.first?.lines.first)
        #expect(row.quantity != nil)
        #expect(row.unitID != nil)
    }

    @Test func fetchFailureSurfacesAsAnError() async {
        do {
            _ = try await RecipeExtractor.extract(
                from: "https://example.com/recipe",
                fetching: { _ in "" },
                now: now, id: "r7")
            Issue.record("expected unreadableHTML")
        } catch let error as ExtractionError {
            #expect(error == .unreadableHTML)
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func fetchedPageWithoutRecipeIsNotARecipe() async {
        do {
            _ = try await RecipeExtractor.extract(
                from: "https://example.com/about",
                fetching: { _ in "<h1>About</h1><p>A company page.</p>" },
                now: now, id: "r8")
            Issue.record("expected notARecipe")
        } catch let error as ExtractionError {
            #expect(error == .notARecipe)
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }
}
