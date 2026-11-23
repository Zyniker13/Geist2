import XCTest

/// Safari end-to-end for the share extension (M3): the driver serves a
/// recipe page on localhost, Safari opens it, the share sheet exposes
/// the extension, the sheet closes once the recipe is written, and the
/// driver then inspects the App Group container to prove the file.
/// The test only asserts the visible half; the shell asserts the rest.
@MainActor
final class SafariShareUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// Screenshots land in the result bundle and a stable temp path
    /// the shell collects for docs/look-dev/.
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

    private func visibleLabels(of app: XCUIApplication) -> String {
        app.descendants(matching: .any)
            .allElementsBoundByIndex.prefix(40)
            .compactMap { $0.label.isEmpty ? nil : $0.label }
            .joined(separator: " | ")
    }

    func testShareFromSafariReachesTheExtension() throws {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()

        let urlField = safari.textFields
            .matching(NSPredicate(format: "label == 'Address'")).firstMatch
        XCTAssertTrue(urlField.waitForExistence(timeout: 15), "no URL bar")
        urlField.tap()
        urlField.typeText("localhost:8123/e2e-recipe.html\n")

        XCTAssertTrue(
            safari.staticTexts["Miso Glazed Carrots"].waitForExistence(timeout: 15),
            "page did not load; \(visibleLabels(of: safari))")
        snap(safari, "share-safari-page")

        // iOS 27 Safari keeps Share inside the Page Menu (⋯).
        let pageMenu = safari.buttons["MoreMenuButton"].firstMatch
        XCTAssertTrue(pageMenu.waitForExistence(timeout: 5), "no Page Menu button")
        pageMenu.tap()

        let shareItem = safari.buttons["Share"].firstMatch
        XCTAssertTrue(shareItem.waitForExistence(timeout: 5), "no Share in Page Menu")
        shareItem.tap()

        let action = safari
            .descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'RecipeApp'"))
            .firstMatch
        let appeared = action.waitForExistence(timeout: 15)
        snap(safari, "share-sheet")
        XCTAssertTrue(
            appeared,
            "Add-to-RecipeApp missing; visible labels: \(visibleLabels(of: safari))")
        action.tap()

        // The extension has no UI: Safari returns to the page when the
        // write lands. The group-container proof belongs to the driver.
        let returned = safari.staticTexts["Miso Glazed Carrots"]
            .waitForExistence(timeout: 15)
        snap(safari, "share-done")
        XCTAssertTrue(returned, "Safari did not return after sharing")
    }
}
