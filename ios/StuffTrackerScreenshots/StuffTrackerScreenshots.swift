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

    func testSearchFindsAnItemByItsDocumentName() throws {
        app.buttons["Search stuff..."].tap()
        let searchField = app.textFields["Search stuff..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.typeText("RECEIPT\n")

        let cameraBag = app.buttons["Camera Bag"]
        XCTAssertTrue(scrollUpUntilHittable(cameraBag))
        XCTAssertTrue(app.staticTexts["Office"].exists)
        XCTAssertFalse(app.buttons["Coffee Filters"].exists)
        let result = XCTAttachment(screenshot: app.screenshot())
        result.name = "Document name search reveals parent item"
        result.lifetime = .keepAlways
        add(result)

        app.buttons["Clear search"].tap()
        XCTAssertTrue(scrollDownUntilHittable(app.buttons["Coffee Filters"]))
    }

    func testPhotoFilterCombinesWithDocuments() throws {
        app.buttons["document-filter"].tap()
        app.buttons["Without photos"].tap()
        XCTAssertTrue(app.staticTexts["Without photos"].waitForExistence(timeout: 5))
        let photoFilter = XCTAttachment(screenshot: app.screenshot())
        photoFilter.name = "Inventory without photos"
        photoFilter.lifetime = .keepAlways
        add(photoFilter)
        app.buttons["document-filter"].tap()
        app.buttons["With documents"].tap()
        XCTAssertTrue(app.staticTexts["With documents · Without photos"].waitForExistence(timeout: 5))
        let combined = XCTAttachment(screenshot: app.screenshot())
        combined.name = "Combined attachment filters"
        combined.lifetime = .keepAlways
        add(combined)
        app.buttons["document-filter"].tap()
        app.buttons["Any photos"].tap()
        XCTAssertTrue(app.buttons["Camera Bag"].waitForExistence(timeout: 5))
    }

    func testDocumentFilterCombinesWithSearchAndCanBeCleared() throws {
        app.buttons["document-filter"].tap()
        app.buttons["With documents"].tap()
        XCTAssertTrue(app.buttons["Camera Bag"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Coffee Filters"].exists)
        XCTAssertTrue(app.staticTexts["Office"].exists)
        let withDocuments = XCTAttachment(screenshot: app.screenshot())
        withDocuments.name = "Inventory with documents"
        withDocuments.lifetime = .keepAlways
        add(withDocuments)

        app.buttons["Search stuff..."].tap()
        app.textFields["Search stuff..."].typeText("RECEIPT\n")
        XCTAssertTrue(app.buttons["Camera Bag"].waitForExistence(timeout: 5))
        app.buttons["document-filter"].tap()
        app.buttons["Without documents"].tap()
        XCTAssertTrue(app.staticTexts["No items without documents"].waitForExistence(timeout: 5))
        let empty = XCTAttachment(screenshot: app.screenshot())
        empty.name = "Document filter with no matching search results"
        empty.lifetime = .keepAlways
        add(empty)

        app.buttons["Clear search"].tap()
        XCTAssertFalse(app.buttons["Camera Bag"].exists)
        XCTAssertTrue(scrollDownUntilHittable(app.buttons["Coffee Filters"]))
        app.buttons["document-filter"].tap()
        app.buttons["All items"].tap()
        XCTAssertTrue(scrollUpUntilHittable(app.buttons["Camera Bag"]))
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

    func testCopyItemLinkPreservesUnsavedEdits() throws {
        app.buttons["Search stuff..."].tap()
        let searchField = app.textFields["Search stuff..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.typeText("camera\n")
        let cameraBag = app.buttons["Camera Bag"]
        XCTAssertTrue(scrollUpUntilHittable(cameraBag))
        cameraBag.tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(" draft")
        app.buttons["Item actions"].tap()
        let copyLink = app.buttons["Copy Item Link"]
        XCTAssertTrue(copyLink.waitForExistence(timeout: 5))
        let menu = XCTAttachment(screenshot: app.screenshot())
        menu.name = "Copy item link menu"
        menu.lifetime = .keepAlways
        add(menu)
        copyLink.tap()

        XCTAssertTrue(app.staticTexts["Item link copied"].waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, "Camera Bag draft")
        let confirmation = XCTAttachment(screenshot: app.screenshot())
        confirmation.name = "Copied link preserves draft"
        confirmation.lifetime = .keepAlways
        add(confirmation)
    }

    func testCopySerialNumberPreservesUnsavedEdits() throws {
        app.buttons["Search stuff..."].tap()
        let searchField = app.textFields["Search stuff..."]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.typeText("camera\n")
        let cameraBag = app.buttons["Camera Bag"]
        XCTAssertTrue(scrollUpUntilHittable(cameraBag))
        cameraBag.tap()
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(" draft")
        app.buttons["Item actions"].tap()
        let copySerial = app.buttons["Copy Serial Number"]
        XCTAssertTrue(copySerial.waitForExistence(timeout: 5))
        XCTAssertTrue(copySerial.isEnabled)
        let menu = XCTAttachment(screenshot: app.screenshot())
        menu.name = "Copy serial number menu"
        menu.lifetime = .keepAlways
        add(menu)
        copySerial.tap()
        XCTAssertTrue(app.staticTexts["Serial number copied"].waitForExistence(timeout: 5))
        XCTAssertEqual(nameField.value as? String, "Camera Bag draft")
        let confirmation = XCTAttachment(screenshot: app.screenshot())
        confirmation.name = "Copied serial preserves draft"
        confirmation.lifetime = .keepAlways
        add(confirmation)
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
