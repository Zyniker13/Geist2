import XCTest

/// Drives the M4.2 recipe view on the simulator: yield scaling, the
/// unit toggle, ingredient check-off, and screenshots into the result
/// bundle (the shell collects them for docs/look-dev/).
final class RecipeViewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

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

    func testScaleUnitsAndCheckOff() throws {
        let app = XCUIApplication()
        app.launch()

        // Seed a recipe through the import sheet (the same path users
        // take), so the test is self-contained.
        let addButton = app.buttons["Import"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "+ button missing")
        addButton.tap()

        let textTab = app.buttons["Text"].firstMatch
        XCTAssertTrue(textTab.waitForExistence(timeout: 5), "Text tab missing")
        textTab.tap()
        let editor = app.textViews["pasteEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "text editor missing")
        editor.tap()
        editor.typeText(
            "Tomato Soup\nMakes 4 servings\n\nIngredients\n- 2 cups vegetable stock\n- 1 lb tomatoes\n- 2 cloves garlic\n- salt to taste\n\nDirections\n1. Simmer the tomatoes in 2 cups of the stock for 20 minutes.\n2. Blend until smooth.\n"
        )
        app.buttons["textImport"].firstMatch.tap()
        let confirmation = app.staticTexts["Saved “Tomato Soup”."]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10), "confirmation missing")
        app.buttons["Cancel"].firstMatch.tap()

        // Open the recipe: the row is a button labeled "title, yield".
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tomato Soup'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "recipe row missing")
        row.tap()

        // The detail shows the as-written ingredient line.
        let asWritten = app.staticTexts["2 cups vegetable stock"].firstMatch
        XCTAssertTrue(asWritten.waitForExistence(timeout: 5), "as-written line missing")
        snap(app, "detail-as-written")

        // Scale the yield up: the ingredient line rescales live.
        let stepper = app.steppers.firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 5), "yield stepper missing")
        stepper.buttons["Increment"].tap()
        // 4 → 5 servings is ×1.25: "2 cups" scales to "2 1/2 cups".
        let scaled = app.staticTexts["2 1/2 cups vegetable stock"].firstMatch
        XCTAssertTrue(scaled.waitForExistence(timeout: 5), "scaled line missing")
        snap(app, "detail-scaled")

        // Switch to metric: the volume line converts (2.5 cups → 591.47 ml).
        let metric = app.buttons["Metric"].firstMatch
        XCTAssertTrue(metric.waitForExistence(timeout: 5), "unit toggle missing")
        metric.tap()
        let metricLine = app.staticTexts["591.47 ml vegetable stock"].firstMatch
        XCTAssertTrue(metricLine.waitForExistence(timeout: 5), "metric line missing")
        snap(app, "detail-metric")

        // Back to written, then check off two lines. Re-query: the
        // toggle rebuilds the list and the old element may be stale.
        // Tap the row's Button, not the StaticText inside it — the text
        // re-resolves as "Other" between snapshot passes and the tap
        // misses ("Automation type mismatch").
        app.buttons["As written"].firstMatch.tap()
        let writtenLine = app.buttons["2 1/2 cups vegetable stock"].firstMatch
        XCTAssertTrue(
            writtenLine.waitForExistence(timeout: 5),
            "written line missing after toggle back")
        writtenLine.tap()
        // 1 lb × 1.25 = 1.25 lb, which the lb rounding step (halves,
        // M2.2's kitchen-friendly rule) snaps to 1 1/2.
        let tomatoes = app.buttons["1 1/2 lbs tomatoes"].firstMatch
        XCTAssertTrue(tomatoes.waitForExistence(timeout: 5), "scaled tomato line missing")
        tomatoes.tap()
        snap(app, "detail-checked-off")
    }
}
