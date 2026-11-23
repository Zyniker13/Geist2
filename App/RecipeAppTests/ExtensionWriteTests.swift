import RecipeCore
import RecipeImport
import XCTest

@testable import RecipeApp

/// Proves the share extension's write path on macOS (M3 "on the Mac"):
/// the same SharedLibrary extract call ShareHandler makes turns what a
/// Safari share delivers — the URL plus the page HTML, or just text —
/// into a recipe document, and LibraryStore writes and reloads it.
/// Writes go to temp roots: the real group container needs an
/// entitlement only the extension has, and the extension's real write
/// is proven by the Safari simulator E2E (decision 0014).
final class ExtensionWriteTests: XCTestCase {
    /// The page fixture a share carries. Kept small and self-made.
    static let misoHTML = """
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

    private func scratchRoot(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("extension-write-tests-\(label)-\(UUID().uuidString)")
    }

    /// A Safari share delivers the URL and the page HTML together.
    /// The handler extracts from the HTML and stamps the shared URL as
    /// the source; the write must land and reload.
    func testSafariShareAttachmentsExtractAndWrite() async throws {
        let extracted = SharedLibrary.extract(
            html: Self.misoHTML, url: "http://example.com/miso-carrots",
            now: 1_760_000_000, id: "e2e-mac-safari")
        let document = try XCTUnwrap(extracted, "extraction returned nothing")
        XCTAssertEqual(document.title, "Miso Glazed Carrots")
        XCTAssertEqual(document.sourceURL, "http://example.com/miso-carrots")
        let ingredientText = document.ingredientSections
            .flatMap(\.lines).map(\.originalText).joined()
        XCTAssertTrue(ingredientText.contains("carrots"))

        let root = scratchRoot("safari")
        let store = LibraryStore(root: root)
        try await store.write(document)

        let reload = try await store.loadRecipe(id: document.id)
        XCTAssertEqual(reload.title, "Miso Glazed Carrots")
        XCTAssertEqual(reload.sourceURL, "http://example.com/miso-carrots")
        try? FileManager.default.removeItem(at: root)
    }

    /// A text-only share (notes, messages) goes through the same
    /// SharedLibrary.extract with text instead of HTML.
    func testTextShareExtractsAndWrites() async throws {
        let text = """
            Lentil Soup
            Serves 4
            Ingredients
            1 cup brown lentils
            1 onion, diced
            2 carrots, diced
            Steps
            1. Sweat the onion and carrots.
            2. Add lentils and 4 cups water; simmer 30 minutes.
            """
        let extracted = SharedLibrary.extract(
            text: text, url: nil, now: 1_760_000_100, id: "e2e-mac-text")
        let document = try XCTUnwrap(extracted, "text extraction returned nothing")
        XCTAssertTrue(document.title.lowercased().contains("lentil"))

        let root = scratchRoot("text")
        let store = LibraryStore(root: root)
        try await store.write(document)

        let reload = try await store.loadRecipe(id: document.id)
        XCTAssertEqual(reload.id, document.id)
        try? FileManager.default.removeItem(at: root)
    }

    /// The handler's precedence, mirrored at the extraction layer:
    /// when both HTML and text ride the share, the HTML wins.
    func testHTMLBeatsTextWhenBothArePresent() throws {
        let extracted = SharedLibrary.extract(
            html: Self.misoHTML,
            text: "Lentil Soup\nIngredients\n1 cup brown lentils\nSteps\n1. Simmer.",
            url: "http://example.com/miso-carrots",
            now: 1_760_000_200, id: "e2e-mac-precedence")
        let document = try XCTUnwrap(extracted)
        XCTAssertEqual(document.title, "Miso Glazed Carrots")
    }
}
