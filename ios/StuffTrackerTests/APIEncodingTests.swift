import XCTest
@testable import StuffTracker

final class APIEncodingTests: XCTestCase {
    func testAPIErrorMessageDecodesBackendErrorPayload() throws {
        let data = try XCTUnwrap(#"{"error":"Admin access required"}"#.data(using: .utf8))

        XCTAssertEqual(
            APIClient.errorMessage(from: data, fallback: "Request failed"),
            "Admin access required"
        )
    }

    func testAPIErrorMessageFallsBackForEmptyPayload() {
        XCTAssertEqual(
            APIClient.errorMessage(from: Data(), fallback: "Request failed"),
            "Request failed"
        )
    }

    func testAPIErrorMessageIncludesValidationDetails() throws {
        let data = try XCTUnwrap(
            #"{"error":"Validation error","details":[{"message":"String must contain at most 100 character(s)","path":["documents",0,"id"]}]}"#
                .data(using: .utf8)
        )

        XCTAssertEqual(
            APIClient.errorMessage(from: data, fallback: "Request failed"),
            "Validation error: documents.0.id: String must contain at most 100 character(s)"
        )
    }

    func testItemBodyEncodesNilLocationAsExplicitNull() throws {
        let body = APIClient.ItemBody(
            name: "Couch 5",
            locationId: nil,
            icon: "sofa.fill",
            notes: nil,
            quantity: 1,
            properties: [],
            photoUrls: [],
            documents: [],
            purchaseDate: nil
        )

        let json = try encodedJSON(body)

        XCTAssertEqual(json["name"] as? String, "Couch 5")
        XCTAssertTrue(json.keys.contains("location_id"))
        XCTAssertTrue(json["location_id"] is NSNull)
        XCTAssertEqual(json["icon"] as? String, "sofa.fill")
        XCTAssertTrue((json["properties"] as? [[String: Any]])?.isEmpty == true)
        XCTAssertEqual(json["photo_urls"] as? [String], [])
        XCTAssertTrue((json["documents"] as? [[String: Any]])?.isEmpty == true)
        XCTAssertFalse(json.keys.contains("tags"))
        XCTAssertFalse(json.keys.contains("purchase_date"))
    }

    func testUpdateLocationBodyEncodesNilParentAsExplicitNull() throws {
        let body = APIClient.UpdateLocationBody(
            name: "Top Floor",
            parentId: nil,
            sortOrder: 0,
            icon: nil
        )

        let json = try encodedJSON(body)

        XCTAssertEqual(json["name"] as? String, "Top Floor")
        XCTAssertTrue(json.keys.contains("parent_id"))
        XCTAssertTrue(json["parent_id"] is NSNull)
        XCTAssertEqual(json["sort_order"] as? Int, 0)
        XCTAssertTrue(json.keys.contains("icon"))
        XCTAssertTrue(json["icon"] is NSNull)
    }

    func testCreateLocationBodyEncodesTopLevelParentAsExplicitNull() throws {
        let body = APIClient.LocationBody(
            name: "Top Floor",
            parentId: nil,
            type: "floor",
            sortOrder: 0,
            icon: nil
        )

        let json = try encodedJSON(body)

        XCTAssertEqual(json["type"] as? String, "floor")
        XCTAssertTrue(json.keys.contains("parent_id"))
        XCTAssertTrue(json["parent_id"] is NSNull)
        XCTAssertTrue(json.keys.contains("icon"))
        XCTAssertTrue(json["icon"] is NSNull)
    }

    func testGoogleSignInBodyKeepsBackendCamelCaseTokenKey() throws {
        let body = APIClient.GoogleSignInBody(idToken: "google-token")

        let json = try encodedJSON(body, keyEncodingStrategy: .useDefaultKeys)

        XCTAssertEqual(json["idToken"] as? String, "google-token")
        XCTAssertFalse(json.keys.contains("id_token"))
    }

    func testAppleSignInBodyKeepsBackendCamelCaseTokenAndNameKeys() throws {
        var name = PersonNameComponents()
        name.givenName = "Jane"
        name.familyName = "Appleseed"
        let body = APIClient.AppleSignInBody(identityToken: "apple-token", fullName: name)

        let json = try encodedJSON(body, keyEncodingStrategy: .useDefaultKeys)
        let fullName = try XCTUnwrap(json["fullName"] as? [String: Any])

        XCTAssertEqual(json["identityToken"] as? String, "apple-token")
        XCTAssertFalse(json.keys.contains("identity_token"))
        XCTAssertEqual(fullName["givenName"] as? String, "Jane")
        XCTAssertEqual(fullName["familyName"] as? String, "Appleseed")
        XCTAssertFalse(fullName.keys.contains("given_name"))
        XCTAssertFalse(fullName.keys.contains("family_name"))
    }

    private func encodedJSON<T: Encodable>(
        _ value: T,
        keyEncodingStrategy: JSONEncoder.KeyEncodingStrategy = .convertToSnakeCase
    ) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = keyEncodingStrategy
        let data = try encoder.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
