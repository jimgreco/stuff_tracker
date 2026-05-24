import XCTest
@testable import StuffTracker

final class ModelBehaviorTests: XCTestCase {
    func testItemDecodingDefaultsMissingServerFields() throws {
        let data = """
        {
          "id": "item-1",
          "home_id": "home-1",
          "name": "Keys"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let item = try decoder.decode(Item.self, from: data)

        XCTAssertEqual(item.id, "item-1")
        XCTAssertEqual(item.homeId, "home-1")
        XCTAssertNil(item.locationId)
        XCTAssertEqual(item.quantity, 1)
        XCTAssertEqual(item.properties, [])
        XCTAssertEqual(item.photoUrls, [])
        XCTAssertEqual(item.documents, [])
        XCTAssertNil(item.serialNumber)
        XCTAssertNil(item.modelNumber)
        XCTAssertNil(item.warrantyExpiresDate)
        XCTAssertNil(item.estimatedValueCents)
        XCTAssertEqual(item.sortOrder, 0)
        XCTAssertEqual(item.createdBy, "")
        XCTAssertFalse(item.needsSync)
    }

    func testHomeDetailTreeHelpersSortLocationsAndItemsBySortOrder() {
        let home = HomeDetail(
            id: "home-1",
            name: "Home",
            ownerId: "owner-1",
            role: "owner",
            icon: nil,
            locations: [
                Location(id: "room-2", homeId: "home-1", parentId: "floor-1", name: "B", type: .room, sortOrder: 2),
                Location(id: "floor-1", homeId: "home-1", parentId: nil, name: "Floor", type: .floor, sortOrder: 1),
                Location(id: "room-1", homeId: "home-1", parentId: "floor-1", name: "A", type: .room, sortOrder: 1),
                Location(id: "floor-0", homeId: "home-1", parentId: nil, name: "Basement", type: .floor, sortOrder: 0),
            ],
            items: [
                Item(id: "item-2", homeId: "home-1", locationId: "room-1", name: "B", sortOrder: 2),
                Item(id: "item-0", homeId: "home-1", locationId: nil, name: "Root", sortOrder: 0),
                Item(id: "item-1", homeId: "home-1", locationId: "room-1", name: "A", sortOrder: 1),
            ]
        )

        XCTAssertEqual(home.topLevelLocations.map(\.id), ["floor-0", "floor-1"])
        XCTAssertEqual(home.children(of: "floor-1").map(\.id), ["room-1", "room-2"])
        XCTAssertEqual(home.items(in: "room-1").map(\.id), ["item-1", "item-2"])
        XCTAssertEqual(home.items(in: nil).map(\.id), ["item-0"])
    }

    func testLocalModelsConvertToApiModelsAndFilterDeletedChildren() {
        let home = LocalHome(
            id: "home-1",
            name: "Home",
            ownerId: "owner-1",
            role: "admin",
            icon: "house",
            needsSync: false
        )
        let activeLocation = LocalLocation(
            id: "loc-1",
            homeId: "home-1",
            name: "Top Floor",
            type: "floor",
            needsSync: false
        )
        let deletedLocation = LocalLocation(
            id: "loc-2",
            homeId: "home-1",
            name: "Old Room",
            type: "room",
            needsSync: false,
            isDeleted: true
        )
        let activeItem = LocalItem(
            id: "item-1",
            homeId: "home-1",
            locationId: "loc-1",
            name: "Couch",
            quantity: 2,
            serialNumber: "SN-1",
            modelNumber: "MOD-1",
            warrantyExpiresDate: "2027-05-24",
            estimatedValueCents: 25000,
            createdBy: "owner-1",
            needsSync: false
        )
        let deletedItem = LocalItem(
            id: "item-2",
            homeId: "home-1",
            name: "Old Couch",
            needsSync: false,
            isDeleted: true
        )

        home.locations = [activeLocation, deletedLocation]
        home.items = [activeItem, deletedItem]

        let apiHome = home.toHome()
        let detail = home.toHomeDetail()

        XCTAssertEqual(apiHome.id, "home-1")
        XCTAssertEqual(apiHome.ownerId, "owner-1")
        XCTAssertEqual(apiHome.role, "admin")
        XCTAssertEqual(activeLocation.toLocation().type, .floor)
        XCTAssertEqual(activeItem.toItem().quantity, 2)
        XCTAssertEqual(activeItem.toItem().serialNumber, "SN-1")
        XCTAssertEqual(activeItem.toItem().modelNumber, "MOD-1")
        XCTAssertEqual(activeItem.toItem().warrantyExpiresDate, "2027-05-24")
        XCTAssertEqual(activeItem.toItem().estimatedValueCents, 25000)
        XCTAssertEqual(detail.locations.map(\.id), ["loc-1"])
        XCTAssertEqual(detail.items.map(\.id), ["item-1"])
    }

    func testHierarchyCollapseStorePersistsCollapsedNodes() {
        let suiteName = "HierarchyCollapseStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        let key = "collapsed-nodes"
        let store = HierarchyCollapseStore(defaults: defaults, key: key)
        XCTAssertFalse(store.isCollapsed(.home("home-1")))
        XCTAssertFalse(store.isCollapsed(.location("room-1")))

        store.toggle(.home("home-1"))
        store.setCollapsed(true, for: .location("room-1"))
        XCTAssertTrue(store.isCollapsed(.home("home-1")))
        XCTAssertTrue(store.isCollapsed(.location("room-1")))

        let reloaded = HierarchyCollapseStore(defaults: defaults, key: key)
        XCTAssertTrue(reloaded.isCollapsed(.home("home-1")))
        XCTAssertTrue(reloaded.isCollapsed(.location("room-1")))

        reloaded.setCollapsed(false, for: .home("home-1"))
        let cleared = HierarchyCollapseStore(defaults: defaults, key: key)
        XCTAssertFalse(cleared.isCollapsed(.home("home-1")))
        XCTAssertTrue(cleared.isCollapsed(.location("room-1")))
    }

    func testHierarchyCollapseStorePrunesRemovedNodes() {
        let suiteName = "HierarchyCollapseStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        let key = "collapsed-nodes"
        let store = HierarchyCollapseStore(defaults: defaults, key: key)
        store.setCollapsed(true, for: .home("home-1"))
        store.setCollapsed(true, for: .location("room-1"))
        store.setCollapsed(true, for: .location("container-1"))

        store.prune(validNodes: [.home("home-1"), .location("container-1")])

        XCTAssertTrue(store.isCollapsed(.home("home-1")))
        XCTAssertFalse(store.isCollapsed(.location("room-1")))
        XCTAssertTrue(store.isCollapsed(.location("container-1")))

        let reloaded = HierarchyCollapseStore(defaults: defaults, key: key)
        XCTAssertTrue(reloaded.isCollapsed(.home("home-1")))
        XCTAssertFalse(reloaded.isCollapsed(.location("room-1")))
        XCTAssertTrue(reloaded.isCollapsed(.location("container-1")))
    }

    func testHierarchyCollapseStoreMigratesLegacyContainerIds() {
        let suiteName = "HierarchyCollapseStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Expected isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        let key = "collapsed-nodes"
        let legacyKey = "legacy-collapsed-containers"
        defaults.set(["container-1"], forKey: legacyKey)

        let store = HierarchyCollapseStore(defaults: defaults, key: key, legacyContainerKey: legacyKey)

        XCTAssertTrue(store.isCollapsed(.location("container-1")))
        XCTAssertEqual(defaults.stringArray(forKey: key), ["location:container-1"])
    }
}
