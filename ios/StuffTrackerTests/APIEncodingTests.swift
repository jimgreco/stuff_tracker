import XCTest
@testable import StuffTracker

final class APIEncodingTests: XCTestCase {
    func testItemBodyEncodesNilLocationAsExplicitNull() throws {
        let body = APIClient.ItemBody(
            name: "Couch 5",
            locationId: nil,
            icon: nil,
            notes: nil,
            quantity: 1,
            tags: nil,
            photoUrl: nil,
            purchaseDate: nil
        )

        let json = try encodedJSON(body)

        XCTAssertEqual(json["name"] as? String, "Couch 5")
        XCTAssertTrue(json.keys.contains("location_id"))
        XCTAssertTrue(json["location_id"] is NSNull)
        XCTAssertFalse(json.keys.contains("tags"))
        XCTAssertFalse(json.keys.contains("purchase_date"))
    }

    func testUpdateLocationBodyEncodesNilParentAsExplicitNull() throws {
        let body = APIClient.UpdateLocationBody(
            name: "Top Floor",
            parentId: nil,
            sortOrder: 0
        )

        let json = try encodedJSON(body)

        XCTAssertEqual(json["name"] as? String, "Top Floor")
        XCTAssertTrue(json.keys.contains("parent_id"))
        XCTAssertTrue(json["parent_id"] is NSNull)
        XCTAssertEqual(json["sort_order"] as? Int, 0)
    }

    func testCreateLocationBodyEncodesTopLevelParentAsExplicitNull() throws {
        let body = APIClient.LocationBody(
            name: "Top Floor",
            parentId: nil,
            type: "floor",
            sortOrder: 0
        )

        let json = try encodedJSON(body)

        XCTAssertEqual(json["type"] as? String, "floor")
        XCTAssertTrue(json.keys.contains("parent_id"))
        XCTAssertTrue(json["parent_id"] is NSNull)
    }

    private func encodedJSON<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
