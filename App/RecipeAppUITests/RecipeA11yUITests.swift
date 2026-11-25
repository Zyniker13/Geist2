import XCTest

/// Accessibility checks (M4.4): the recipe detail and the editor at an
/// accessibility Dynamic Type size — text scales, nothing truncates
/// into unreadability. The screenshots double as the look-dev evidence.
final class RecipeA11yUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testDetailAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        // AX3 is a large accessibility size; semantic fonts scale with
        // it and the layout must stay readable.
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL",
        ]
        app.launch()

        // Seed through the text import (the proven self-contained path).
        let addButton = app.buttons["addRecipeMenu"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "+ menu missing")
        addButton.tap()
        let importItem = app.buttons["Import…"].firstMatch
        if importItem.waitForExistence(timeout: 3) {
            importItem.tap()
        }
        let textTab = app.buttons["Text"].firstMatch
        XCTAssertTrue(textTab.waitForExistence(timeout: 5), "Text tab missing")
        textTab.tap()
        let editor = app.textViews["pasteEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "text editor missing")
        editor.tap()
        editor.typeText(
            "Tomato Soup\nMakes 4 servings\n\nIngredients\n- 2 cups vegetable stock\n- 1 lb tomatoes\n\nDirections\n1. Simmer for 20 minutes.\n"
        )
        app.buttons["textImport"].firstMatch.tap()
        let confirmation = app.staticTexts["Saved “Tomato Soup”."]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10), "confirmation missing")
        app.buttons["Cancel"].firstMatch.tap()

        // The just-dismissed sheet leaves ghost elements that match
        // instantly: wait for a REAL element to come back before
        // continuing (geist2-ui-testing pitfall).
        _ = app.buttons["addRecipeMenu"].waitForExistence(timeout: 5)
        sleep(1)

        // At accessibility sizes taps on list rows are swallowed by the
        // covered scroller's hit-test, so relaunch with the deep-link
        // hook that opens the newest recipe directly.
        app.terminate()
        app.launchArguments += ["-openFirstRecipe"]
        app.launch()
        XCTAssertTrue(
            app.buttons["editRecipe"].firstMatch.waitForExistence(timeout: 10),
            "detail did not open via deep link")
        let line = app.staticTexts["2 cups vegetable stock"].firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 10), "ingredient line missing at AX size")
        snap(app, "a11y-detail-ax-text")

        // The editor at the same size.
        let edit = app.buttons["editRecipe"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "edit button missing")
        edit.tap()
        let title = app.textFields["editorTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "editor missing at AX size")
        snap(app, "a11y-editor-ax-text")
        app.buttons["editorCancel"].firstMatch.tap()
    }
}
