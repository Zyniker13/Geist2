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
        // The test serves its own page so it works in any runner context
        // (safari-e2e.sh and the plain `test` run alike).
        let server = TinyHTTPServer(port: 8123, html: Self.recipeHTML)
        try server.start()
        defer { server.stop() }

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

        let action =
            safari
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
        // write lands. The runner holds the App Group entitlement, so it
        // can wait for the recipe file itself — that both proves the
        // extension really saved a recipe and keeps the HTTP server
        // alive until the extension's fetch is done.
        let returned = safari.staticTexts["Miso Glazed Carrots"]
            .waitForExistence(timeout: 15)
        snap(safari, "share-done")
        XCTAssertTrue(returned, "Safari did not return after sharing")

        // Prove the data half end to end: the extension wrote into the
        // shared App Group, so the app's own library — which reads the
        // same group — must now list the recipe.
        let app = XCUIApplication(bundleIdentifier: "com.bristleconeit.geist2")
        app.terminate()
        app.launch()
        snap(app, "share-written")
        XCTAssertTrue(
            app.staticTexts["Miso Glazed Carrots"].waitForExistence(timeout: 20),
            "the app library did not show the recipe the extension saved")
    }

    /// The reduced, self-written page the test serves (no third-party
    /// text; the same shape the fixtures use).
    private static let recipeHTML = """
        <!doctype html><html><head><meta charset="utf-8">
        <title>Miso Glazed Carrots</title></head>
        <body><h1>Miso Glazed Carrots</h1>
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Recipe","name":"Miso Glazed Carrots",
         "recipeYield":"4 servings",
         "recipeIngredient":["1 lb carrots, peeled and sliced","2 tbsp white miso",
                             "1 tbsp honey","1 tbsp rice vinegar"],
         "recipeInstructions":[{"@type":"HowToStep","text":"Roast the carrots."},
                               {"@type":"HowToStep","text":"Glaze with the miso mixture."}]}
        </script></body></html>
        """
}

/// Minimal HTTP server for the UI-test runner process: one route,
/// localhost only, one connection at a time.
final class TinyHTTPServer {
    private var socketFD: Int32 = -1
    private var listenerThread: Thread?

    init(port: Int, html: String) {
        self.port = port
        self.html = html
    }

    func start() throws {
        socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { throw ServerError.cannotOpen }
        var yes: Int32 = 1
        setsockopt(
            socketFD, Int32(SOL_SOCKET), Int32(SO_REUSEADDR), &yes,
            socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_ANY)
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(socketFD, 4) == 0 else {
            throw ServerError.cannotBind
        }

        let thread = Thread { [weak self] in self?.acceptLoop() }
        thread.name = "e2e-http"
        thread.start()
        listenerThread = thread
    }

    func stop() {
        if socketFD >= 0 { close(socketFD) }
        socketFD = -1
    }

    private func acceptLoop() {
        let body = html.data(using: .utf8)!
        let head =
            "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        while socketFD >= 0 {
            var clientAddr = sockaddr()
            var len = socklen_t(MemoryLayout<sockaddr>.size)
            let fd = accept(socketFD, &clientAddr, &len)
            guard fd >= 0 else { break }
            var buffer = [UInt8](repeating: 0, count: 4096)
            _ = read(fd, &buffer, buffer.count)
            _ = head.data(using: .utf8)!.withUnsafeBytes {
                send(fd, $0.baseAddress, head.utf8.count, 0)
            }
            body.withUnsafeBytes { send(fd, $0.baseAddress, body.count, 0) }
            close(fd)
        }
    }

    private let port: Int
    private let html: String

    enum ServerError: Error { case cannotOpen, cannotBind }
}
