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
}
