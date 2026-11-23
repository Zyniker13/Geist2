import RecipeCore
import RecipeImport
import XCTest
@testable import RecipeApp

/// Proves the share extension's write path: the same SharedLibrary
/// extract call ShareHandler makes turns the HTML an HTML email or
/// page share carries into a recipe document, and LibraryStore writes
/// and reloads it (M3 "on the Mac"). The write goes to a temp root —
/// the real group container needs an entitlement only the extension
/// has, and the extension's real write is proven by the Safari E2E.
final class ExtensionWriteTests: XCTestCase {
    /// A host application gives the test an extension-like sandbox.
    func testExtractedHTMLWritesIntoAScratchRoot() async throws {
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

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("extension-write-tests-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try await store.write(document)

        let reload = try await store.loadRecipe(id: document.id)
        XCTAssertEqual(reload.title, "Miso Glazed Carrots")
        try? FileManager.default.removeItem(at: root)
    }
}
