import XCTest

/// Drives the real import flow on the simulator: open the sheet, paste
/// text, import, and screenshot each stage into docs/look-dev/. The
/// screenshots are captured from inside the test, so they exist even
/// when an assertion fails.
final class ImportFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// Screenshots land in the result bundle and in a stable temp path
    /// the shell can collect for docs/look-dev/.
    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let image = app.screenshot().pngRepresentation
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("uitest-\(name).png")
        try? image.write(to: url)
    }

    func testImportThroughTheTextTab() throws {
        let app = XCUIApplication()
        app.launch()

        // The library opens empty; the import sheet opens from +.
        let addButton = app.buttons["Import"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "+ button missing")
        snap(app, "library-empty")
        addButton.tap()

        // Switch to the Text tab.
        let textTab = app.buttons["Text"].firstMatch
        XCTAssertTrue(textTab.waitForExistence(timeout: 5), "Text tab missing")
        textTab.tap()
        snap(app, "import-text-tab")

        // Type the recipe into the editor.
        let editor = app.textViews["pasteEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "text editor missing")
        editor.tap()
        editor.typeText(
            "Lemon Cake\nMakes 8 slices\n\nIngredients\n- 2 cups flour\n- 1 cup sugar\n- 3 eggs\n\nDirections\n1. Whisk the eggs with the sugar.\n2. Fold in the flour.\n3. Bake 35 minutes.\n"
        )

        let submit = app.buttons["textImport"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5), "submit button missing")
        submit.tap()

        // The sheet shows the saved confirmation, then closes on Cancel.
        let confirmation = app.staticTexts["Saved “Lemon Cake”."]
        XCTAssertTrue(
            confirmation.waitForExistence(timeout: 10),
            "confirmation missing")
        snap(app, "import-saved")

        app.buttons["Cancel"].firstMatch.tap()
        // The list now shows the recipe.
        let row = app.staticTexts["Lemon Cake"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "recipe row missing")
        snap(app, "library-with-recipe")
        row.tap()
        XCTAssertTrue(
            app.staticTexts["2 cups flour"].waitForExistence(timeout: 5),
            "detail missing ingredient line")
        snap(app, "recipe-detail")
    }
}
