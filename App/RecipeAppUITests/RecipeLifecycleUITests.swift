import XCTest

/// The M4 done-when flows the recipe view tests do not cover: editing
/// an existing recipe from its detail, and deleting one with the
/// confirmation alert.
final class RecipeLifecycleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Seeds a recipe through the editor and opens its detail.
    @discardableResult
    private func seedRecipe(_ app: XCUIApplication, title: String) throws -> XCUIElement {
        let addMenu = app.buttons["addRecipeMenu"].firstMatch
        XCTAssertTrue(addMenu.waitForExistence(timeout: 10), "+ menu missing")
        addMenu.tap()
        let newRecipe = app.buttons["New recipe"].firstMatch
        XCTAssertTrue(newRecipe.waitForExistence(timeout: 5), "New recipe missing")
        newRecipe.tap()
        let titleField = app.textFields["editorTitle"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "editor title missing")
        titleField.tap()
        titleField.typeText(title)
        let save = app.buttons["editorSave"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), "save missing")
        save.tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '\(title)'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "row missing after save")
        row.tap()
        XCTAssertTrue(
            app.staticTexts[title].firstMatch.waitForExistence(timeout: 5),
            "detail missing")
        return row
    }

    func testEditRecipeFromDetail() throws {
        let app = XCUIApplication()
        app.launch()

        _ = try seedRecipe(app, title: "Editable Stew")

        // The detail's Edit button opens the editor with the fields
        // filled.
        let edit = app.buttons["editRecipe"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "edit button missing")
        edit.tap()
        let titleField = app.textFields["editorTitle"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "editor did not open")
        snap(app, "edit-existing-open")

        // Change the title and save.
        titleField.tap()
        titleField.press(forDuration: 0.9)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) {
            selectAll.tap()
        }
        titleField.typeText("Renamed Stew")
        let save = app.buttons["editorSave"].firstMatch
        save.tap()

        // The detail reloads with the new title (the sheet dismissal
        // triggers the view model's reload).
        let renamed = app.staticTexts["Renamed Stew"].firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 10), "detail did not reload")
        snap(app, "edit-existing-saved")

        // The list shows the new title too.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Renamed Stew'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "list did not refresh")
    }

    func testDeleteRecipeWithConfirmation() throws {
        let app = XCUIApplication()
        app.launch()

        _ = try seedRecipe(app, title: "Doomed Soup")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Long-press the row for the context menu, then Delete.
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Doomed Soup'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "row missing")
        row.press(forDuration: 1.1)
        let deleteItem = app.buttons["Delete"].firstMatch
        XCTAssertTrue(deleteItem.waitForExistence(timeout: 5), "context menu Delete missing")
        deleteItem.tap()

        // The confirmation alert; confirm.
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "confirmation missing")
        confirm.tap()

        // The row disappears.
        let gone = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Doomed Soup'"))
            .firstMatch
        XCTAssertFalse(gone.waitForExistence(timeout: 5), "row still listed after delete")
        snap(app, "deleted")
    }
}
