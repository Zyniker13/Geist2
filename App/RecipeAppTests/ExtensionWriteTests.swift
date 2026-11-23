import RecipeCore
import RecipeImport
import XCTest
@testable import RecipeApp

/// Proves the share extension's write path on macOS: the same
/// SharedLibrary.extract call ShareHandler makes turns the HTML an
/// HTML email or page share carries into a recipe document, and the
/// LibraryStore write into SharedLibrary.root lands (M3 "on the Mac").
final class ExtensionWriteTests: XCTestCase {
    /// A host application gives the test an extension-like sandbox.
    func testExtractedHTMLWritesIntoTheSharedRoot() async throws {
        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head><meta charset="utf-8"><title>Miso Glazed Carrots</title>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "Recipe",
          "name": "Miso Glazed Carrots",
          "recipeYield": "4 servings",
          "recipeIngredient": ["1 lb carrots", "2 tbsp white miso"],
          "recipeInstructions": ["Steam the carrots.", "Glaze and roast."]
        }
        </script></head>
        <body><h1>Miso Glazed Carrots</h1></body>
        </html>
        """
        let extracted = SharedLibrary.extract(
            html: html, url: "http://example.com/miso-carrots",
            now: 1_760_000_000, id: "e2e-mac")
        let document = try XCTUnwrap(
            extracted, "extraction returned nothing")
        XCTAssertEqual(document.title, "Miso Glazed Carrots")
        XCTAssertEqual(document.sourceURL, "http://example.com/miso-carrots")
        let ingredientText = document.ingredientSections.flatMap(\.lines).map(\.originalText).joined()
        XCTAssertTrue(ingredientText.contains("carrots"))

        let store = LibraryStore(root: SharedLibrary.root)
        try await store.write(document)

        let reload = try await store.loadRecipe(id: document.id)
        XCTAssertEqual(reload.title, "Miso Glazed Carrots")
    }
}
