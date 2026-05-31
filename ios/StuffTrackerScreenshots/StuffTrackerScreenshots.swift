import XCTest

@MainActor
final class StuffTrackerScreenshots: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments += [
            "--app-store-screenshots",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launchEnvironment["APP_STORE_SCREENSHOTS"] = "1"
        app.launch()

        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts["Maple House"].waitForExistence(timeout: 15))
    }

    func testAppStoreScreenshots() throws {
        snapshot("01-Home-Hierarchy")

        app.buttons["Show flagged items"].tap()
        XCTAssertTrue(app.staticTexts["Passports"].waitForExistence(timeout: 5))
        snapshot("02-Flagged-Items")

        app.buttons["Showing flagged items"].tap()
        let searchField = app.textFields["Search stuff..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        app.typeText("camera\n")
        XCTAssertTrue(app.staticTexts["Camera Bag"].waitForExistence(timeout: 5))
        snapshot("03-Search")

        app.staticTexts["Camera Bag"].tap()
        XCTAssertTrue(app.navigationBars["Edit Item"].waitForExistence(timeout: 5))
        snapshot("04-Item-Details")
    }
}
