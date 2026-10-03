import XCTest
import SwiftData
import SwiftUI
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
        XCTAssertTrue(
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


private final class AccountBoundaryURLProtocol: URLProtocol {
    static var handler: ((AccountBoundaryURLProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(self) }
    override func stopLoading() {}
    func respond(_ status: Int, _ json: String = "{}") {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class NativeAccountBoundaryTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let defaultsName = "cubby-account-boundary-test-\(UUID().uuidString)"
        let defaults: UserDefaults
        let local: LocalDataManager
        let api: APIClient
        let auth: AuthStore
        let sync: SyncManager
        let accountA = User(id: "account-a", email: "a@example.test", name: "A", avatarUrl: nil)
        let accountB = User(id: "account-b", email: "b@example.test", name: "B", avatarUrl: nil)
        init() {
            defaults = UserDefaults(suiteName: defaultsName)!
            local = LocalDataManager(inMemory: true, accountDefaults: defaults)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [AccountBoundaryURLProtocol.self]
            api = APIClient(session: URLSession(configuration: configuration))
            api.clearAuthTokens()
            auth = AuthStore(api: api, local: local, restoreSession: false)
            sync = SyncManager(api: api, local: local)
        }
        func signIn(_ user: User) throws {
            try auth.acceptVerifiedUser(user, response: AuthResponse(token: "synthetic-\(user.id)", refreshToken: "synthetic-refresh", user: user))
        }
        func cleanup() {
            auth.signOut()
            defaults.removePersistentDomain(forName: defaultsName)
            UserDefaults.standard.removeObject(forKey: AuthStore.completedAuthenticationDefaultsKey)
            AccountBoundaryURLProtocol.handler = nil
        }
    }

    @MainActor
    func testSignOutPreservesInventoryAndRejectsDifferentAccount() throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        let home = f.local.createHome(name: "Unsynced private inventory")
        f.auth.signOut()
        XCTAssertNil(f.api.localAccountID)
        XCTAssertTrue(f.auth.requiresSignIn)
        try f.signIn(f.accountB)
        XCTAssertFalse(f.auth.isAuthenticated)
        XCTAssertFalse(f.api.hasToken)
        XCTAssertEqual(f.local.boundAccountID, f.accountA.id)
        XCTAssertEqual(f.local.fetchHomes().first?.id, home.id)
        XCTAssertTrue(home.needsSync)
        try f.signIn(f.accountA)
        XCTAssertEqual(f.auth.currentUser?.id, f.accountA.id)
    }

    @MainActor
    func testLegacyInventoryRequiresExplicitClaimAndCancelPreservesIt() throws {
        let f = Fixture(); defer { f.cleanup() }
        let home = f.local.createHome(name: "Unattributed legacy data")
        try f.signIn(f.accountA)
        XCTAssertFalse(f.auth.isAuthenticated)
        XCTAssertNil(f.api.localAccountID)
        XCTAssertNil(f.local.boundAccountID)
        XCTAssertEqual(f.auth.pendingInventoryClaim?.id, f.accountA.id)
        f.auth.signOut()
        f.auth.confirmInventoryClaim() // stale confirmation does nothing
        XCTAssertNil(f.local.boundAccountID)
        XCTAssertEqual(f.local.fetchHomes().first?.id, home.id)
        try f.signIn(f.accountA)
        f.auth.confirmInventoryClaim()
        XCTAssertEqual(f.local.boundAccountID, f.accountA.id)
        XCTAssertEqual(f.api.localAccountID, f.accountA.id)
        XCTAssertTrue(home.needsSync)
    }

    @MainActor
    func testTombstonesAndLegacyQueuePreventAccountReassignment() throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        let home = f.local.createHome(name: "Deleted offline")
        f.local.deleteHome(home)
        XCTAssertTrue(f.local.fetchHomes().isEmpty)
        XCTAssertEqual(try f.local.bindAccount(userID: f.accountB.id), .differentAccount)
        f.local.hardDelete(home: home)
        f.local.context!.insert(SyncOperation(entityType: "home", entityId: "synthetic", operation: "delete"))
        f.local.save()
        XCTAssertEqual(try f.local.bindAccount(userID: f.accountB.id), .differentAccount)
    }

    @MainActor
    func testFailedHomeListDoesNotUploadOrRemoveLocalData() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        let home = f.local.createHome(name: "Pending")
        var methods: [String] = []
        AccountBoundaryURLProtocol.handler = { request in
            methods.append(request.request.httpMethod!)
            request.respond(503, "{\"error\":\"Unavailable\"}")
        }
        await f.sync.performFullSync()
        XCTAssertEqual(methods, ["GET"])
        XCTAssertTrue(home.needsSync)
        XCTAssertEqual(f.local.fetchHomes().first?.id, home.id)
        XCTAssertNotNil(f.sync.syncError)
    }

    @MainActor
    func testFailedReplacementDetailPreservesCompleteLocalStore() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        let home = f.local.createHome(name: "Keep this")
        AccountBoundaryURLProtocol.handler = { request in
            if request.request.url!.path == "/homes" {
                request.respond(200, "[{\"id\":\"remote\",\"name\":\"Remote\",\"owner_id\":\"account-a\",\"role\":\"owner\"}]")
            } else { request.respond(500) }
        }
        await f.sync.replaceLocalWithServer()
        XCTAssertEqual(f.local.fetchHomes().map(\.id), [home.id])
        XCTAssertTrue(home.needsSync)
    }

    @MainActor
    func testFailedDeleteRetainsTombstoneUntilConfirmedMissing() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        let home = f.local.createHome(name: "Delete later")
        f.local.deleteHome(home)
        AccountBoundaryURLProtocol.handler = { $0.respond(503) }
        await f.sync.syncPendingChanges()
        XCTAssertEqual(f.local.fetchDeletedHomes().map(\.id), [home.id])
        AccountBoundaryURLProtocol.handler = { $0.respond(404) }
        await f.sync.syncPendingChanges()
        XCTAssertTrue(f.local.fetchDeletedHomes().isEmpty)
    }

    @MainActor
    func testForbiddenHomeIsNotRecreatedAsNewHome() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        let home = f.local.createHome(name: "Revoked home")
        var methods: [String] = []
        AccountBoundaryURLProtocol.handler = { request in
            methods.append(request.request.httpMethod!)
            if request.request.url!.path == "/homes" { request.respond(200, "[]") }
            else { request.respond(403) }
        }
        await f.sync.performFullSync()
        XCTAssertFalse(methods.contains("POST"))
        XCTAssertTrue(home.needsSync)
    }

    @MainActor
    func testLateHomeResponseAfterSignOutCannotMergeOrContinueSync() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        let home = f.local.createHome(name: "Private retained home")
        home.needsSync = false
        f.local.save()
        var count = 0
        AccountBoundaryURLProtocol.handler = { request in
            count += 1
            Task { @MainActor in
                f.auth.signOut()
                request.respond(200, "[{\"id\":\"late\",\"name\":\"Late response\",\"owner_id\":\"account-a\",\"role\":\"owner\"}]")
            }
        }
        await f.sync.performFullSync()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(f.local.fetchHomes().map(\.id), [home.id])
        XCTAssertNil(f.api.localAccountID)
        XCTAssertFalse(f.auth.isAuthenticated)
    }

    @MainActor
    func testFailedStoredIdentityFetchLocksInventoryWithoutClearingDataOrToken() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let home = f.local.createHome(name: "Saved inventory")
        XCTAssertEqual(try f.local.bindAccount(userID: f.accountA.id, claimLegacy: true), .allowed)
        f.api.setAuthTokens(token: "synthetic-stored-token", refreshToken: nil)
        AccountBoundaryURLProtocol.handler = { $0.respond(503) }
        await f.auth.restoreStoredSession()
        XCTAssertFalse(f.auth.isAuthenticated)
        XCTAssertTrue(f.auth.requiresSignIn)
        XCTAssertNil(f.api.localAccountID)
        XCTAssertEqual(SecureTokenStore.token, "synthetic-stored-token")
        XCTAssertEqual(f.local.fetchHomes().map(\.id), [home.id])
    }

    @MainActor
    func testLegacyInventoryClaimScreen() async throws {
        let f = Fixture(); defer { f.cleanup() }
        _ = f.local.createHome(name: "Synthetic inventory")
        try f.signIn(f.accountA)
        let controller = UIHostingController(rootView: LoginView(mode: .reconnect).environmentObject(f.auth))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.windowLevel = .alert + 1
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 250_000_000)
        let rendered = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let screenshot = XCTAttachment(image: rendered)
        screenshot.name = "Legacy inventory claim — synthetic account"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertNotNil(f.auth.pendingInventoryClaim)
        XCTAssertFalse(f.auth.isAuthenticated)
    }

    @MainActor
    func testLateRefreshCannotOverwriteNewSession() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        AccountBoundaryURLProtocol.handler = { request in
            if request.request.url!.path == "/auth/refresh" {
                Task { @MainActor in
                    f.auth.signOut()
                    try f.signIn(f.accountB) // empty retained store may be reassigned
                    request.respond(200, "{\"token\":\"old-token\",\"refresh_token\":\"old-refresh\",\"user\":{\"id\":\"account-a\",\"name\":\"A\",\"email\":\"a@example.test\"}}")
                }
            } else { request.respond(401) }
        }
        do {
            let _: [Home] = try await f.api.listHomes()
            XCTFail("Old request should have been cancelled")
        } catch is CancellationError { }
        catch { XCTFail("Expected cancellation, received \(error)") }
        XCTAssertEqual(SecureTokenStore.token, "synthetic-account-b")
        XCTAssertEqual(f.api.localAccountID, f.accountB.id)
    }
}
