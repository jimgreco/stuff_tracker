import XCTest
@testable import StuffTracker

final class SyncUploadPlannerTests: XCTestCase {
    func testOrdersLocationsParentBeforeChildRegardlessOfInputOrder() throws {
        let locations = [
            PendingSyncLocation(
                id: "room",
                parentId: "floor",
                name: "Living Room",
                needsSync: true,
                isDeleted: false
            ),
            PendingSyncLocation(
                id: "container",
                parentId: "room",
                name: "Couch",
                needsSync: true,
                isDeleted: false
            ),
            PendingSyncLocation(
                id: "floor",
                parentId: nil,
                name: "Top Floor",
                needsSync: true,
                isDeleted: false
            ),
        ]

        let orderedIds = try SyncUploadPlanner.orderedPendingLocationIds(locations)

        XCTAssertEqual(orderedIds, ["floor", "room", "container"])
    }

    func testIncludesCleanParentBeforePendingChildIsUploaded() throws {
        let locations = [
            PendingSyncLocation(
                id: "room",
                parentId: "floor",
                name: "Living Room",
                needsSync: true,
                isDeleted: false
            ),
            PendingSyncLocation(
                id: "floor",
                parentId: nil,
                name: "Top Floor",
                needsSync: false,
                isDeleted: false
            ),
        ]

        let orderedIds = try SyncUploadPlanner.orderedPendingLocationIds(locations)

        XCTAssertEqual(orderedIds, ["room"])
    }

    func testThrowsWhenPendingLocationReferencesMissingParent() {
        let locations = [
            PendingSyncLocation(
                id: "room",
                parentId: "missing-floor",
                name: "Living Room",
                needsSync: true,
                isDeleted: false
            ),
        ]

        XCTAssertThrowsError(try SyncUploadPlanner.orderedPendingLocationIds(locations)) { error in
            XCTAssertEqual(
                error as? SyncUploadPlanningError,
                .missingParent(locationName: "Living Room")
            )
        }
    }

    func testThrowsWhenLocationParentsAreCyclic() {
        let locations = [
            PendingSyncLocation(
                id: "a",
                parentId: "b",
                name: "A",
                needsSync: true,
                isDeleted: false
            ),
            PendingSyncLocation(
                id: "b",
                parentId: "a",
                name: "B",
                needsSync: true,
                isDeleted: false
            ),
        ]

        XCTAssertThrowsError(try SyncUploadPlanner.orderedPendingLocationIds(locations)) { error in
            XCTAssertEqual(error as? SyncUploadPlanningError, .cyclicLocation(locationName: "A"))
        }
    }

    func testServerMergePolicyKeepsPendingLocalChanges() {
        XCTAssertFalse(ServerMergePolicy.shouldApplyServerRecord(needsSync: true, isDeleted: false))
        XCTAssertFalse(ServerMergePolicy.shouldApplyServerRecord(needsSync: false, isDeleted: true))
        XCTAssertTrue(ServerMergePolicy.shouldApplyServerRecord(needsSync: false, isDeleted: false))
    }
}
