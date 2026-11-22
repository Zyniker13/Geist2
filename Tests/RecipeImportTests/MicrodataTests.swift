import Foundation
import RecipeCore
import Testing

@testable import RecipeImport

/// The HTML reader underneath the microdata extractor.
struct HTMLTreeTests {
    @Test func parsesNestedElementsAndText() {
        let root = HTMLTree.parse("<div id=a><p>One</p><p>Two</p></div>")
        let div = root.children[0]
        #expect(div.tag == "div")
        #expect(div.attribute("id") == "a")
        #expect(div.children.count == 2)
        #expect(div.children[0].text == "One")
        #expect(div.children[1].text == "Two")
    }

    @Test func voidElementsAndSelfClosing() {
        let root = HTMLTree.parse("<div><br><img src=x><span/><span>ok</span></div>")
        let div = root.children[0]
        #expect(div.children.count == 4)
        #expect(div.children[0].tag == "br")
        #expect(div.children[1].tag == "img")
        #expect(div.children[2].tag == "span")
        #expect(div.children[3].tag == "span")
        #expect(div.children[3].text == "ok")
    }

    @Test func quotedAttributesMayContainAngleBrackets() {
        let root = HTMLTree.parse(#"<a title="a > b" href="/x">link</a>"#)
        let a = root.children[0]
        #expect(a.attribute("title") == "a > b")
        #expect(a.attribute("href") == "/x")
        #expect(a.text == "link")
    }

    @Test func scriptContentIsNotMarkup() {
        let root = HTMLTree.parse(
            "<body><script>if (a < b && c > d) { x(); }</script><p>after</p></body>")
        let body = root.children[0]
        // The script element stays in the tree, but its content is
        // data: no child elements, no text, and the `<` characters
        // inside it did not become markup.
        #expect(body.children.count == 2)
        #expect(body.children[0].tag == "script")
        #expect(body.children[0].text.isEmpty)
        #expect(body.children[0].children.isEmpty)
        #expect(body.children[1].tag == "p")
        #expect(body.children[1].text == "after")
    }

    @Test func commentsAndDoctypeAreSkipped() {
        let root = HTMLTree.parse(
            "<!doctype html><!-- a <div> comment --><p>text</p>")
        #expect(root.children.count == 1)
        #expect(root.children[0].text == "text")
    }

    @Test func unclosedTagsEndAtParentClose() {
        let root = HTMLTree.parse("<div><span>open</div>")
        let div = root.children[0]
        #expect(div.children.count == 1)
        #expect(div.children[0].tag == "span")
        #expect(div.children[0].text == "open")
    }

    @Test func textAccumulatesAcrossChildren() {
        let root = HTMLTree.parse("<p>Hello <b>bold</b> world</p>")
        let p = root.children[0]
        #expect(p.children[0].text == "bold")
        #expect(p.text.contains("Hello"))
        #expect(p.text.contains("world"))
    }
}

/// Microdata extraction.
struct MicrodataExtractorTests {
    @Test func extractsCompleteRecipe() throws {
        let html = """
            <div itemscope itemtype="https://schema.org/Recipe">
              <h1 itemprop="name">Test Bread</h1>
              <p itemprop="description">A loaf.</p>
              <span itemprop="recipeYield">1 loaf</span>
              <span itemprop="recipeCuisine">French</span>
              <meta itemprop="prepTime" content="PT20M">
              <meta itemprop="cookTime" content="PT1H">
              <ul>
                <li itemprop="recipeIngredient">2 cups flour</li>
                <li itemprop="recipeIngredient">1 tsp salt</li>
              </ul>
              <ol>
                <li itemprop="recipeInstructions">Mix the flour.</li>
                <li itemprop="recipeInstructions">Knead 10 minutes.</li>
              </ol>
              <img itemprop="image" src="https://example.com/bread.jpg">
            </div>
            """
        let recipe = try #require(MicrodataExtractor.extract(from: html))
        #expect(recipe.name == "Test Bread")
        #expect(recipe.description == "A loaf.")
        #expect(recipe.recipeYield == "1 loaf")
        #expect(recipe.recipeCuisine == "French")
        #expect(recipe.prepTime == "PT20M")
        #expect(recipe.cookTime == "PT1H")
        #expect(recipe.ingredients == ["2 cups flour", "1 tsp salt"])
        #expect(recipe.instructions == ["Mix the flour.", "Knead 10 minutes."])
        #expect(recipe.images == ["https://example.com/bread.jpg"])
    }

    @Test func nestedAuthorAndNutritionItems() throws {
        let html = """
            <div itemscope itemtype="https://schema.org/Recipe">
              <span itemprop="name">Stew</span>
              <div itemprop="author" itemscope itemtype="https://schema.org/Person">
                <span itemprop="name">Test Author</span>
              </div>
              <div itemprop="nutrition" itemscope itemtype="https://schema.org/NutritionInformation">
                <span itemprop="calories">300 kcal</span>
                <span itemprop="proteinContent">12 g</span>
              </div>
            </div>
            """
        let recipe = try #require(MicrodataExtractor.extract(from: html))
        #expect(recipe.author == "Test Author")
        #expect(recipe.nutrition["calories"] == "300 kcal")
        #expect(recipe.nutrition["proteinContent"] == "12 g")
    }

    @Test func howToSectionInsideInstructions() throws {
        let html = """
            <div itemscope itemtype="https://schema.org/Recipe">
              <span itemprop="name">Layered</span>
              <div itemprop="recipeInstructions" itemscope itemtype="https://schema.org/HowToSection">
                <span itemprop="name">Make the base</span>
                <div itemprop="itemListElement" itemscope itemtype="https://schema.org/HowToStep">
                  <span itemprop="text">Mix it.</span>
                </div>
                <div itemprop="itemListElement" itemscope itemtype="https://schema.org/HowToStep">
                  <span itemprop="text">Add water.</span>
                </div>
              </div>
            </div>
            """
        let recipe = try #require(MicrodataExtractor.extract(from: html))
        #expect(recipe.instructionSections.count == 1)
        #expect(recipe.instructionSections[0].name == "Make the base")
        #expect(recipe.instructionSections[0].steps == ["Mix it.", "Add water."])
    }

    @Test func itempropAsSpaceSeparatedList() throws {
        let html = """
            <div itemscope itemtype="https://schema.org/Recipe">
              <span itemprop="name">Two</span>
              <a itemprop="image thumbnailUrl" href="https://example.com/pic.jpg">view</a>
            </div>
            """
        let recipe = try #require(MicrodataExtractor.extract(from: html))
        #expect(recipe.images == ["https://example.com/pic.jpg"])
    }

    @Test func secondRecipeOnPageIsNotTaken() throws {
        // The first Recipe item wins.
        let html = """
            <div itemscope itemtype="https://schema.org/Recipe">
              <span itemprop="name">First</span>
              <span itemprop="recipeIngredient">1 cup water</span>
            </div>
            <div itemscope itemtype="https://schema.org/Recipe">
              <span itemprop="name">Second</span>
            </div>
            """
        let recipe = try #require(MicrodataExtractor.extract(from: html))
        #expect(recipe.name == "First")
    }

    @Test func nonRecipeMicrodataReturnsNil() {
        let html = """
            <div itemscope itemtype="https://schema.org/Organization">
              <span itemprop="name">Example Co</span>
            </div>
            """
        #expect(MicrodataExtractor.extract(from: html) == nil)
    }

    @Test func urlValuesComeFromHrefAndSrc() throws {
        let html = """
            <div itemscope itemtype="https://schema.org/Recipe">
              <span itemprop="name">Urls</span>
              <link itemprop="image" href="https://example.com/cover.jpg">
            </div>
            """
        let recipe = try #require(MicrodataExtractor.extract(from: html))
        #expect(recipe.images == ["https://example.com/cover.jpg"])
    }
}
