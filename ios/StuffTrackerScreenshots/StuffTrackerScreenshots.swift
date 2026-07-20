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
        let searchButton = app.buttons["Search stuff..."]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        searchButton.tap()

        let searchField = app.textFields["Search stuff..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        app.typeText("camera\n")
        XCTAssertTrue(app.staticTexts["Camera Bag"].waitForExistence(timeout: 5))
        snapshot("03-Search")

        app.staticTexts["Camera Bag"].tap()
        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 5))
        snapshot("04-Item-Details")
    }

    func testNewContainerAppearsImmediatelyInItsRoom() throws {
        let searchButton = app.buttons["Search stuff..."]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        searchButton.tap()

        let searchField = app.textFields["Search stuff..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.typeText("coffee\n")
        XCTAssertTrue(app.staticTexts["Coffee Filters"].waitForExistence(timeout: 5))

        app.buttons["location-menu-screenshot-location-kitchen"].tap()

        let addContainer = app.buttons["Add Container"]
        XCTAssertTrue(addContainer.waitForExistence(timeout: 5))
        addContainer.tap()

        let nameField = app.textFields["Container name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.typeText("Serving Bin")
        app.buttons["Add container"].tap()

        XCTAssertTrue(app.staticTexts["Serving Bin"].waitForExistence(timeout: 5))
    }
}
