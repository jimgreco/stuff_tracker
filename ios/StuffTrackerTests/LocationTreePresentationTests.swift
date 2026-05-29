import XCTest
@testable import StuffTracker

final class LocationTreePresentationTests: XCTestCase {
    func testSelectedLabelHandlesMissingHomeAndTopLevelSelection() {
        XCTAssertEqual(LocationTreePresentation.selectedLabel(home: nil, selectedId: nil), "None")

        let home = makeHome()

        XCTAssertEqual(LocationTreePresentation.selectedLabel(home: home, selectedId: nil), "Home")
        XCTAssertEqual(LocationTreePresentation.selectedLabel(home: home, selectedId: "missing"), "Home")
    }

    func testSelectedLabelBuildsLocationBreadcrumb() {
        let home = makeHome()

        XCTAssertEqual(
            LocationTreePresentation.selectedLabel(home: home, selectedId: "bin"),
            "Top Floor › Living Room › Media Bin"
        )
    }

    func testInitialNavigationPathOpensAncestorsOfSelectedLocation() {
        let home = makeHome()

        XCTAssertEqual(
            LocationTreePresentation.initialNavigationPath(home: home, selectedId: "bin"),
            ["floor", "room"]
        )
        XCTAssertEqual(
            LocationTreePresentation.initialNavigationPath(home: home, selectedId: "floor"),
            []
        )
        XCTAssertEqual(
            LocationTreePresentation.initialNavigationPath(home: home, selectedId: nil),
            []
        )
    }

    func testIconUsesCustomIconThenFallsBackByLocationType() {
        XCTAssertEqual(LocationTreePresentation.icon(for: makeLocation(id: "floor", type: .floor)), "building.2")
        XCTAssertEqual(LocationTreePresentation.icon(for: makeLocation(id: "room", type: .room)), "door.left.hand.closed")
        XCTAssertEqual(LocationTreePresentation.icon(for: makeLocation(id: "bin", type: .container)), "square.stack.3d.up")
        XCTAssertEqual(
            LocationTreePresentation.icon(for: makeLocation(id: "custom", type: .room, icon: "sofa.fill")),
            "sofa.fill"
        )
    }

    func testItemShareFormatterSharesLocationOnly() {
        let text = ItemShareFormatter.text(
            for: makeItem(name: "HDMI Cable", locationId: "bin"),
            home: makeHome(),
            scope: .location
        )

        XCTAssertEqual(
            text,
            """
            HDMI Cable
            Location: Home › Top Floor › Living Room › Media Bin
            Open in Stuff Tracker: https://stuff-tracker.jim-greco.com/items/home-1/item-1
            """
        )
    }

    func testItemShareFormatterSharesDetailsOnly() {
        let text = ItemShareFormatter.text(
            for: makeItem(
                name: "Camera",
                notes: "Keep with the charger.",
                quantity: 2,
                properties: [
                    ItemProperty(key: "Color", value: "Black"),
                    ItemProperty(key: "Empty Value", value: "  "),
                    ItemProperty(key: " ", value: "Skipped")
                ],
                photoUrls: ["https://example.com/photo.jpg"],
                documents: [
                    ItemDocument(url: "https://example.com/manual.pdf", name: "Manual.pdf")
                ],
                purchaseDate: "2026-05-01",
                serialNumber: "SN123",
                modelNumber: "MOD456",
                warrantyExpiresDate: "2027-05-01",
                estimatedValueCents: 12999
            ),
            home: makeHome(),
            scope: .details
        )

        XCTAssertEqual(
            text,
            """
            Camera
            Quantity: 2
            Notes: Keep with the charger.
            Serial Number: SN123
            Model Number: MOD456
            Purchase Date: 2026-05-01
            Warranty Expires: 2027-05-01
            Estimated Value: $129.99
            Color: Black
            Empty Value
            Documents: Manual.pdf
            Photos: 1 photo
            Open in Stuff Tracker: https://stuff-tracker.jim-greco.com/items/home-1/item-1
            """
        )
        XCTAssertFalse(text.contains("https://example.com"))
    }

    func testItemShareFormatterSharesLocationAndDetails() {
        let text = ItemShareFormatter.text(
            for: makeItem(name: "Loose Keys", locationId: nil, quantity: 1),
            home: makeHome(),
            scope: .locationAndDetails
        )

        XCTAssertEqual(
            text,
            """
            Loose Keys
            Location: Home
            Quantity: 1
            Open in Stuff Tracker: https://stuff-tracker.jim-greco.com/items/home-1/item-1
            """
        )
    }

    func testItemDeepLinkParsesUniversalItemURLs() {
        let link = ItemDeepLink(homeId: "home-1", itemId: "item-1")

        XCTAssertEqual(link.url.absoluteString, "https://stuff-tracker.jim-greco.com/items/home-1/item-1")
        XCTAssertEqual(ItemDeepLink.itemAnchorID("item-1"), "item:item-1")
        XCTAssertEqual(ItemDeepLink(url: link.url), link)
        XCTAssertNil(ItemDeepLink(url: URL(string: "https://stuff-tracker.jim-greco.com")!))
        XCTAssertNil(ItemDeepLink(url: URL(string: "https://example.com/items/home-1/item-1")!))
        XCTAssertNil(ItemDeepLink(url: URL(string: "stuff://item?homeId=home-1&itemId=item-1")!))
    }

    private func makeHome() -> HomeDetail {
        HomeDetail(
            id: "home-1",
            name: "Home",
            ownerId: "owner-1",
            role: "owner",
            icon: nil,
            locations: [
                makeLocation(id: "floor", name: "Top Floor", type: .floor),
                makeLocation(id: "room", parentId: "floor", name: "Living Room", type: .room),
                makeLocation(id: "bin", parentId: "room", name: "Media Bin", type: .container),
            ],
            items: []
        )
    }

    private func makeLocation(
        id: String,
        parentId: String? = nil,
        name: String = "Location",
        type: Location.LocationType,
        icon: String? = nil
    ) -> Location {
        Location(
            id: id,
            homeId: "home-1",
            parentId: parentId,
            name: name,
            type: type,
            sortOrder: 0,
            icon: icon
        )
    }

    private func makeItem(
        name: String,
        locationId: String? = nil,
        notes: String? = nil,
        quantity: Int = 1,
        properties: [ItemProperty] = [],
        photoUrls: [String] = [],
        documents: [ItemDocument] = [],
        purchaseDate: String? = nil,
        serialNumber: String? = nil,
        modelNumber: String? = nil,
        warrantyExpiresDate: String? = nil,
        estimatedValueCents: Int? = nil
    ) -> Item {
        Item(
            id: "item-1",
            homeId: "home-1",
            locationId: locationId,
            name: name,
            notes: notes,
            quantity: quantity,
            properties: properties,
            photoUrls: photoUrls,
            documents: documents,
            purchaseDate: purchaseDate,
            serialNumber: serialNumber,
            modelNumber: modelNumber,
            warrantyExpiresDate: warrantyExpiresDate,
            estimatedValueCents: estimatedValueCents
        )
    }
}
