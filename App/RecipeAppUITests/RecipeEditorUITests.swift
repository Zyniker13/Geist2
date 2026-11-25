import XCTest

/// Drives the M4.3 editor on the simulator: create a recipe through the
/// "+" menu, fill ingredient rows and steps, save, and confirm the
/// detail shows the saved structure. Screenshots into the result bundle.
final class RecipeEditorUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testCreateRecipeThroughEditor() throws {
        let app = XCUIApplication()
        app.launch()

        let addMenu = app.buttons["addRecipeMenu"].firstMatch
        XCTAssertTrue(addMenu.waitForExistence(timeout: 10), "+ menu missing")
        addMenu.tap()

        let newRecipe = app.buttons["New recipe"].firstMatch
        XCTAssertTrue(newRecipe.waitForExistence(timeout: 5), "New recipe item missing")
        newRecipe.tap()

        // The editor sheet: title, one starter ingredient row, one
        // starter step.
        let title = app.textFields["editorTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "editor title missing")
        title.tap()
        title.typeText("Pancakes")

        let yieldAmount = app.textFields["editorYieldAmount"].firstMatch
        XCTAssertTrue(yieldAmount.exists, "yield amount missing")
        yieldAmount.tap()
        yieldAmount.typeText("8")
        let yieldUnit = app.textFields["editorYieldUnit"].firstMatch
        yieldUnit.tap()
        // The field prefills "servings": select all and replace.
        yieldUnit.press(forDuration: 0.9)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) {
            selectAll.tap()
        }
        yieldUnit.typeText("pancakes")

        // The first ingredient row's fields (three text fields per row).
        let ingredientFields = app.textFields.matching(
            NSPredicate(format: "placeholderValue IN {'Amount', 'Unit', 'Ingredient'}"))
        XCTAssertTrue(ingredientFields.count >= 3, "ingredient row fields missing")
        ingredientFields.element(boundBy: 0).tap()
        ingredientFields.element(boundBy: 0).typeText("2")
        ingredientFields.element(boundBy: 1).tap()
        ingredientFields.element(boundBy: 1).typeText("cups")
        ingredientFields.element(boundBy: 2).tap()
        ingredientFields.element(boundBy: 2).typeText("flour")

        // The step field (a vertical TextField exposes as TextField,
        // not TextView) and a timer-bearing text.
        let stepField = app.textFields.matching(
            NSPredicate(format: "placeholderValue == 'Step'")
        ).firstMatch
        XCTAssertTrue(stepField.waitForExistence(timeout: 5), "step field missing")
        stepField.tap()
        stepField.typeText("Whisk and rest for 10 minutes.")

        snap(app, "editor-filled")

        let save = app.buttons["editorSave"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "save missing")
        save.tap()

        // Back on the list: the row exists; open it.
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pancakes'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "saved recipe row missing")
        snap(app, "editor-saved-list")
        row.tap()

        // The detail shows the saved line and the step's timer chip.
        XCTAssertTrue(
            app.staticTexts["2 cups flour"].waitForExistence(timeout: 5),
            "saved ingredient line missing")
        XCTAssertTrue(
            app.staticTexts["Whisk and rest for 10 minutes."].waitForExistence(timeout: 5),
            "saved step missing")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '10m'")).firstMatch
                .waitForExistence(timeout: 5),
            "timer chip missing")
        snap(app, "editor-saved-detail")
    }
}
