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
        let passports = app.buttons["Passports"]
        XCTAssertTrue(scrollUpUntilHittable(passports))
        snapshot("02-Flagged-Items")

        app.buttons["Showing flagged items"].tap()
        let searchButton = app.buttons["Search stuff..."]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        searchButton.tap()

        let searchField = app.textFields["Search stuff..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        app.typeText("camera\n")
        let cameraBag = app.buttons["Camera Bag"]
        XCTAssertTrue(scrollUpUntilHittable(cameraBag))
        snapshot("03-Search")

        cameraBag.tap()
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
        XCTAssertTrue(scrollUpUntilHittable(app.buttons["Coffee Filters"]))

        let kitchenMenu = app.buttons["location-menu-screenshot-location-kitchen"]
        XCTAssertTrue(scrollDownUntilHittable(kitchenMenu))
        kitchenMenu.tap()

        let addContainer = app.buttons["Add Container"]
        XCTAssertTrue(addContainer.waitForExistence(timeout: 5))
        addContainer.tap()

        let nameField = app.textFields["Container name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.typeText("Serving Bin")
        app.buttons["Add container"].tap()

        XCTAssertTrue(app.staticTexts["Serving Bin"].waitForExistence(timeout: 5))
    }

    func testScrollingUpdatesBreadcrumb() throws {
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 5))

        let breadcrumb = app.descendants(matching: .any)["breadcrumb-bar"]
        for _ in 0..<3 where !breadcrumb.exists {
            scrollView.swipeUp(velocity: .fast)
        }

        XCTAssertTrue(breadcrumb.waitForExistence(timeout: 5))
    }

    private func scrollUpUntilHittable(_ element: XCUIElement, attempts: Int = 6) -> Bool {
        scrollUntilHittable(element, attempts: attempts) {
            $0.swipeUp(velocity: .fast)
        }
    }

    private func scrollDownUntilHittable(_ element: XCUIElement, attempts: Int = 6) -> Bool {
        scrollUntilHittable(element, attempts: attempts) {
            $0.swipeDown(velocity: .fast)
        }
    }

    private func scrollUntilHittable(
        _ element: XCUIElement,
        attempts: Int,
        swipe: (XCUIElement) -> Void
    ) -> Bool {
        if element.waitForExistence(timeout: 1), element.isHittable {
            return true
        }

        let scrollView = app.scrollViews.firstMatch
        guard scrollView.waitForExistence(timeout: 2) else { return false }

        for _ in 0..<attempts {
            swipe(scrollView)
            if element.waitForExistence(timeout: 0.5), element.isHittable {
                return true
            }
        }

        return element.exists && element.isHittable
    }
}
