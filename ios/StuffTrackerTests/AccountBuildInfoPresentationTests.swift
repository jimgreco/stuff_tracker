import XCTest
@testable import StuffTracker

final class AccountBuildInfoPresentationTests: XCTestCase {
    func testBuildInfoTextIncludesVersionBuildAndGitHash() {
        let text = AccountBuildInfoPresentation.text(info: [
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "42",
            "GitCommitHash": "abc1234",
        ])

        XCTAssertEqual(text, "Version 1.2.3 (42) - abc1234")
    }

    func testBuildInfoTextFallsBackWhenBundleValuesAreMissing() {
        XCTAssertEqual(
            AccountBuildInfoPresentation.text(info: [:]),
            "Version Unknown (Unknown) - Unknown"
        )
        XCTAssertEqual(
            AccountBuildInfoPresentation.text(info: nil),
            "Version Unknown (Unknown) - Unknown"
        )
    }
}

final class AuthStoreSessionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        resetStoredSession()
    }

    override func tearDown() {
        resetStoredSession()
        super.tearDown()
    }

    func testStoredSessionCheckUsesSecureTokenStore() {
        UserDefaults.standard.removeObject(forKey: "jwt_token")
        SecureTokenStore.token = "stored-token"

        XCTAssertTrue(AuthStore.hasStoredSession)
    }

    func testStoredSessionCheckMigratesLegacyDefaultsToken() {
        SecureTokenStore.token = nil
        UserDefaults.standard.set("legacy-token", forKey: "jwt_token")

        XCTAssertTrue(AuthStore.hasStoredSession)
        XCTAssertEqual(SecureTokenStore.token, "legacy-token")
        XCTAssertNil(UserDefaults.standard.string(forKey: "jwt_token"))
    }

    func testRestoreFailureClearsOnlyInvalidStoredSessions() {
        XCTAssertTrue(
            AuthStore.shouldClearStoredSession(after: APIError.httpError(401, "Invalid or expired token"))
        )
        XCTAssertTrue(
            AuthStore.shouldClearStoredSession(after: APIError.httpError(404, "User not found"))
        )
        XCTAssertFalse(
            AuthStore.shouldClearStoredSession(after: APIError.httpError(500, "Server error"))
        )
        XCTAssertFalse(
            AuthStore.shouldClearStoredSession(after: APIError.networkError(URLError(.notConnectedToInternet)))
        )
        XCTAssertFalse(
            AuthStore.shouldClearStoredSession(
                after: APIError.decodingError(
                    DecodingError.dataCorrupted(
                        .init(codingPath: [], debugDescription: "Bad payload")
                    )
                )
            )
        )
    }

    func testSignInRequiredOnlyAfterAuthenticationWasCompleted() {
        XCTAssertFalse(
            AuthStore.shouldRequireSignIn(
                hasCompletedAuthentication: false,
                hasStoredSession: false,
                isAuthenticated: false,
                isRestoringSession: false
            )
        )
        XCTAssertTrue(
            AuthStore.shouldRequireSignIn(
                hasCompletedAuthentication: true,
                hasStoredSession: false,
                isAuthenticated: false,
                isRestoringSession: false
            )
        )
        XCTAssertFalse(
            AuthStore.shouldRequireSignIn(
                hasCompletedAuthentication: true,
                hasStoredSession: true,
                isAuthenticated: false,
                isRestoringSession: false
            )
        )
        XCTAssertFalse(
            AuthStore.shouldRequireSignIn(
                hasCompletedAuthentication: true,
                hasStoredSession: false,
                isAuthenticated: true,
                isRestoringSession: false
            )
        )
        XCTAssertFalse(
            AuthStore.shouldRequireSignIn(
                hasCompletedAuthentication: true,
                hasStoredSession: false,
                isAuthenticated: false,
                isRestoringSession: true
            )
        )
    }

    func testAuthenticationCompletionPersistsReturningUserState() {
        XCTAssertFalse(AuthStore.hasCompletedAuthentication)

        AuthStore.markAuthenticationCompleted()

        XCTAssertTrue(AuthStore.hasCompletedAuthentication)
    }

    private func resetStoredSession() {
        SecureTokenStore.token = nil
        UserDefaults.standard.removeObject(forKey: "jwt_token")
        UserDefaults.standard.removeObject(forKey: AuthStore.completedAuthenticationDefaultsKey)
    }
}
