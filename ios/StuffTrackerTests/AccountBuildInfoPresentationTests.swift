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
    static var supportsReceipts = true
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.supportsReceipts && request.url?.path == "/account/sync-capabilities" {
            respond(200, "{\"client_create_receipts\":1}")
        } else { Self.handler?(self) }
    }
    func failConnection() { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)) }
    func bodyJSON() -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
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
            AccountBoundaryURLProtocol.supportsReceipts = true
        }
    }

    @MainActor
    func testSignOutLocksInventoryAndSwitchesAccountsWithoutLosingPendingChanges() throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        let home = f.local.createHome(name: "Unsynced private inventory")
        f.auth.signOut()
        XCTAssertNil(f.api.localAccountID)
        XCTAssertTrue(f.auth.requiresSignIn)
        try f.signIn(f.accountB)
        XCTAssertTrue(f.auth.isAuthenticated)
        XCTAssertEqual(f.local.boundAccountID, f.accountB.id)
        XCTAssertTrue(f.local.fetchHomes().isEmpty)
        _ = f.local.createHome(name: "B inventory")
        try f.signIn(f.accountA)
        XCTAssertEqual(f.auth.currentUser?.id, f.accountA.id)
        XCTAssertEqual(f.local.fetchHomes().first?.id, home.id)
        XCTAssertTrue(f.local.fetchHomes().first!.needsSync)
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
        XCTAssertTrue(f.local.fetchHomes().isEmpty)
        try f.signIn(f.accountA)
        XCTAssertEqual(try JSONDecoder().decode(InventoryArchive.self, from: f.auth.inventoryRecoveryData()).homes.first?.id, home.id)
        f.auth.confirmInventoryClaim()
        XCTAssertEqual(f.local.boundAccountID, f.accountA.id)
        XCTAssertEqual(f.api.localAccountID, f.accountA.id)
        XCTAssertTrue(home.needsSync)
    }

    @MainActor
    func testTombstonesAndLegacyQueueStayWithTheirAccount() throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        let home = f.local.createHome(name: "Deleted offline")
        f.local.deleteHome(home)
        f.local.context!.insert(SyncOperation(entityType: "home", entityId: "synthetic", operation: "delete"))
        f.local.save()
        try f.signIn(f.accountB)
        XCTAssertTrue(f.local.fetchDeletedHomes().isEmpty)
        XCTAssertEqual(try f.local.context!.fetchCount(FetchDescriptor<SyncOperation>()), 0)
        try f.signIn(f.accountA)
        XCTAssertEqual(f.local.fetchDeletedHomes().map(\.id), [home.id])
        XCTAssertEqual(try f.local.context!.fetchCount(FetchDescriptor<SyncOperation>()), 1)
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
    func testFailedDeleteRetainsTombstoneUntilAcknowledged() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        let home = f.local.createHome(name: "Delete later")
        f.local.deleteHome(home)
        AccountBoundaryURLProtocol.handler = { $0.respond(503) }
        await f.sync.syncPendingChanges()
        XCTAssertEqual(f.local.fetchDeletedHomes().map(\.id), [home.id])
        AccountBoundaryURLProtocol.handler = { $0.respond(204) }
        await f.sync.syncPendingChanges()
        XCTAssertTrue(f.local.fetchDeletedHomes().isEmpty)
    }

    @MainActor
    func testForbiddenHomeIsNotRecreatedAsNewHome() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        let home = f.local.createHome(name: "Revoked home")
        home.clientCreateID = nil
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
        XCTAssertTrue(f.local.fetchHomes().isEmpty)
        XCTAssertNil(f.api.localAccountID)
        XCTAssertFalse(f.auth.isAuthenticated)
        try f.signIn(f.accountA)
        XCTAssertEqual(f.local.fetchHomes().map(\.id), [home.id])
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
    @MainActor
    func testSkipAndLaterRecoverKeepsIndependentAccountData() throws {
        let f = Fixture(); defer { f.cleanup() }
        let legacy = f.local.createHome(name: "Older offline home")
        try f.signIn(f.accountA)
        let recoveryData = try f.auth.inventoryRecoveryData()
        f.auth.continueWithoutLegacyInventory()
        XCTAssertTrue(f.auth.isAuthenticated)
        XCTAssertTrue(f.auth.hasLegacyRecovery)
        XCTAssertTrue(f.local.fetchHomes().isEmpty)
        let newer = f.local.createHome(name: "New account home")
        f.auth.beginInventoryRecovery()
        XCTAssertEqual(try f.auth.inventoryRecoveryData(), recoveryData)
        f.auth.confirmInventoryClaim()
        XCTAssertEqual(Set(f.local.fetchHomes().map(\.id)), Set([legacy.id, newer.id]))
        XCTAssertFalse(f.auth.hasLegacyRecovery)
        f.auth.signOut()
        try f.signIn(f.accountB)
        XCTAssertTrue(f.local.fetchHomes().isEmpty)
        try f.signIn(f.accountA)
        XCTAssertEqual(f.local.fetchHomes().count, 2) // no duplicate import
    }

    @MainActor
    func testLegacyRecoveryConflictsPreserveBothStoresAndAllowExport() throws {
        let f = Fixture(); defer { f.cleanup() }
        let legacy = f.local.createHome(name: "Original")
        try f.signIn(f.accountA)
        f.auth.continueWithoutLegacyInventory()
        let collision = LocalHome(id: legacy.id, name: "Independent account version")
        f.local.context!.insert(collision)
        f.local.save()
        f.auth.beginInventoryRecovery()
        let original = try f.auth.inventoryRecoveryData()
        f.auth.confirmInventoryClaim()
        XCTAssertFalse(f.auth.isAuthenticated)
        XCTAssertNotNil(f.auth.errorMessage)
        XCTAssertEqual(try f.auth.inventoryRecoveryData(), original)
        f.auth.continueWithoutLegacyInventory()
        XCTAssertEqual(f.local.fetchHomes().map(\.name), ["Independent account version"])
    }

    @MainActor
    func testMidSyncSwitchAllowsNewAccountSyncAndDiscardsOldResponse() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        let oldHome = f.local.createHome(name: "A pending")
        let started = expectation(description: "A request started")
        var held: AccountBoundaryURLProtocol?
        AccountBoundaryURLProtocol.handler = { request in
            if request.request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-account-a" {
                held = request
                started.fulfill()
            } else { request.respond(200, "[]") }
        }
        let oldSync = Task { await f.sync.performFullSync() }
        await fulfillment(of: [started], timeout: 3)
        f.auth.signOut()
        try f.signIn(f.accountB)
        await f.sync.performFullSync()
        XCTAssertNotNil(f.sync.lastSyncDate)
        let newDate = f.sync.lastSyncDate
        held?.respond(200, "[]")
        await oldSync.value
        XCTAssertTrue(f.local.fetchHomes().isEmpty)
        XCTAssertNil(f.sync.syncError)
        XCTAssertEqual(f.sync.lastSyncDate, newDate)
        try f.signIn(f.accountA)
        XCTAssertEqual(f.local.fetchHomes().map(\.id), [oldHome.id])
        XCTAssertTrue(f.local.fetchHomes().first!.needsSync)
    }

    @MainActor
    func testLateDeleteAfterAccountSwitchCannotDeleteMatchingRecord() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        let old = f.local.createHome(name: "Delete in A")
        f.local.deleteHome(old)
        AccountBoundaryURLProtocol.handler = { request in
            Task { @MainActor in
                f.auth.signOut()
                try f.signIn(f.accountB)
                f.local.context!.insert(LocalHome(id: old.id, name: "Same shared home in B"))
                f.local.save()
                request.respond(204)
            }
        }
        await f.sync.syncPendingChanges()
        XCTAssertEqual(f.local.fetchHomes().map(\.id), [old.id])
        XCTAssertNil(f.sync.syncError)
        try f.signIn(f.accountA)
        XCTAssertEqual(f.local.fetchDeletedHomes().map(\.id), [old.id])
    }

    @MainActor
    func testLateSubscriptionResponseDoesNotExposePriorPlanOrError() async throws {
        let f = Fixture(); defer { f.cleanup() }
        let subscription = SubscriptionStore(api: f.api, local: f.local, listenForUpdates: false)
        try f.signIn(f.accountA)
        var calls = 0
        AccountBoundaryURLProtocol.handler = { request in
            calls += 1
            Task { @MainActor in
                f.auth.signOut()
                try f.signIn(f.accountB)
                request.respond(200, "{\"tier\":\"pro\",\"is_paid\":true,\"limits\":{\"homes\":10,\"total_containers_and_items\":10,\"images\":10,\"documents\":10},\"usage\":{\"homes\":1,\"containers\":1,\"items\":1,\"total_containers_and_items\":2,\"images\":1,\"documents\":1},\"remaining\":{}}")
            }
        }
        await subscription.refresh()
        XCTAssertEqual(calls, 1)
        XCTAssertNil(subscription.plan)
        XCTAssertNil(subscription.errorMessage)
        XCTAssertFalse(subscription.isLoading)
    }
    @MainActor
    private func exerciseCreateReplay(kind: String, switchAccount: Bool, deleteAfterLostReply: Bool) async throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        let home = f.local.createHome(name: "Server home")
        home.needsSync = false
        home.clientCreateID = nil
        let homeID = home.id
        let entityID: String
        if kind == "location" { entityID = f.local.createLocation(homeId: homeID, name: "Pending", parentId: nil, type: "container")!.id }
        else { entityID = f.local.createItem(homeId: homeID, name: "Pending", locationId: nil)!.id }
        f.local.save()
        var exists = false
        var creates = 0
        var deletes = 0
        let path = "/homes/\(homeID)/\(kind == "location" ? "locations" : "items")"
        let record: [String: Any] = kind == "location"
            ? ["id": entityID, "home_id": homeID, "name": "Pending", "type": "container", "sort_order": 0]
            : ["id": entityID, "home_id": homeID, "name": "Pending", "quantity": 1, "created_by": f.accountA.id]
        let json = String(data: try JSONSerialization.data(withJSONObject: record), encoding: .utf8)!
        AccountBoundaryURLProtocol.handler = { request in
            let method = request.request.httpMethod!
            if request.request.url!.path == "/homes/\(homeID)" {
                let detail: [String: Any] = ["id": homeID, "name": "Server home", "owner_id": f.accountA.id,
                    "role": "owner", "locations": kind == "location" && exists ? [record] : [],
                    "items": kind == "item" && exists ? [record] : []]
                request.respond(200, String(data: try! JSONSerialization.data(withJSONObject: detail), encoding: .utf8)!)
            } else if method == "PATCH" { request.respond(exists ? 200 : 404, exists ? json : "{}") }
            else if method == "POST" {
                XCTAssertEqual(request.request.url!.path, path)
                XCTAssertEqual(request.bodyJSON()["client_id"] as? String, entityID)
                creates += 1
                exists = true // remote commit happened before this reply was lost/fenced
                if switchAccount {
                    Task { @MainActor in
                        f.auth.signOut()
                        try f.signIn(f.accountB)
                        request.respond(201, json)
                    }
                } else { request.failConnection() }
            } else if method == "DELETE" {
                XCTAssertEqual(URLComponents(url: request.request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, entityID)
                deletes += 1
                exists = false
                if deletes == 1 { request.failConnection() } else { request.respond(204) }
            } else { XCTFail("Unexpected request \(method)"); request.respond(500) }
        }
        await f.sync.syncPendingChanges()
        if switchAccount {
            XCTAssertEqual(f.auth.currentUser?.id, f.accountB.id)
            XCTAssertTrue(f.local.fetchHomes().isEmpty)
            f.auth.signOut()
            try f.signIn(f.accountA)
        }
        XCTAssertEqual(creates, 1)
        if kind == "location" {
            XCTAssertTrue(f.local.fetchLocation(id: entityID)!.needsSync)
            XCTAssertEqual(f.local.fetchLocation(id: entityID)!.clientCreateID, entityID)
            if deleteAfterLostReply { f.local.deleteLocation(f.local.fetchLocation(id: entityID)!) }
        } else {
            XCTAssertTrue(f.local.fetchItem(id: entityID)!.needsSync)
            XCTAssertEqual(f.local.fetchItem(id: entityID)!.clientCreateID, entityID)
            if deleteAfterLostReply { f.local.deleteItem(f.local.fetchItem(id: entityID)!) }
        }
        await f.sync.syncPendingChanges()
        if deleteAfterLostReply {
            XCTAssertEqual(kind == "location" ? f.local.fetchDeletedLocations().count : f.local.fetchDeletedItems().count, 1)
            await f.sync.syncPendingChanges()
            XCTAssertEqual(kind == "location" ? f.local.fetchDeletedLocations().count : f.local.fetchDeletedItems().count, 0)
            XCTAssertEqual(deletes, 2)
            XCTAssertFalse(exists)
        } else {
            XCTAssertFalse(kind == "location" ? f.local.fetchLocation(id: entityID)!.needsSync : f.local.fetchItem(id: entityID)!.needsSync)
            XCTAssertTrue(exists)
        }
        XCTAssertEqual(creates, 1, "Retry must reconcile original UUID, never POST a new row")
    }

    @MainActor
    func testItemAndLocationLostCreateRepliesRetryWithoutDuplicates() async throws {
        for kind in ["item", "location"] { try await exerciseCreateReplay(kind: kind, switchAccount: false, deleteAfterLostReply: false) }
    }

    @MainActor
    func testItemAndLocationCreatesFencedByAccountSwitchRetryOriginalUUID() async throws {
        for kind in ["item", "location"] { try await exerciseCreateReplay(kind: kind, switchAccount: true, deleteAfterLostReply: false) }
    }

    @MainActor
    func testDeleteAfterLostCreateOrAccountSwitchRetainsTombstoneUntilRetryAcknowledged() async throws {
        for kind in ["item", "location"] {
            for switched in [false, true] { try await exerciseCreateReplay(kind: kind, switchAccount: switched, deleteAfterLostReply: true) }
        }
    }

    @MainActor
    func testLegacyUnknownOutcomesStayPendingAndExportableWithoutCreateOrDelete() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        let home = f.local.createHome(name: "Known server home")
        home.needsSync = false
        home.clientCreateID = nil
        let item = f.local.createItem(homeId: home.id, name: "Uncertain old item", locationId: nil)!
        item.clientCreateID = nil
        let location = f.local.createLocation(homeId: home.id, name: "Uncertain old location", parentId: nil, type: "container")!
        location.clientCreateID = nil
        let deleted = f.local.createItem(homeId: home.id, name: "Unknown older deletion", locationId: nil)!
        deleted.clientCreateID = nil
        f.local.deleteItem(deleted)
        var writes = 0
        AccountBoundaryURLProtocol.handler = { request in
            if request.request.httpMethod == "GET" {
                request.respond(200, "{\"id\":\"\(home.id)\",\"name\":\"Known server home\",\"owner_id\":\"account-a\",\"role\":\"owner\",\"locations\":[],\"items\":[]}")
            } else if request.request.httpMethod == "PATCH" { request.respond(404) }
            else { writes += 1; request.respond(500) }
        }
        await f.sync.syncPendingChanges()
        XCTAssertEqual(writes, 0)
        XCTAssertTrue(item.needsSync)
        XCTAssertTrue(location.needsSync)
        XCTAssertEqual(f.local.fetchDeletedItems().map(\.id), [deleted.id])
        let exported = try JSONDecoder().decode(InventoryArchive.self, from: f.auth.currentInventoryData())
        XCTAssertEqual(exported.items.count, 2)
        XCTAssertEqual(exported.locations.count, 1)
        XCTAssertNotNil(f.sync.syncError)
    }

    @MainActor
    func testOldServerCannotReceiveNewDurableCreateOrCancellation() async throws {
        let f = Fixture(); defer { f.cleanup() }
        try f.signIn(f.accountA)
        AccountBoundaryURLProtocol.supportsReceipts = false
        var effects = 0
        AccountBoundaryURLProtocol.handler = { request in
            if request.request.httpMethod != "GET" { effects += 1 }
            request.respond(404)
        }
        let id = UUID().uuidString.lowercased()
        do { _ = try await f.api.createLocation(homeId: UUID().uuidString, name: "Unsent", parentId: nil, type: "room", clientID: id); XCTFail("Expected unsupported server") } catch { }
        do { try await f.api.deleteItem(homeId: UUID().uuidString, itemId: id, clientID: id); XCTFail("Expected unsupported server") } catch { }
        XCTAssertEqual(effects, 0)
    }

}


final class AccountStoreMigrationTests: XCTestCase {
    @MainActor
    private func withDiskFixture(_ test: (URL, URL, UserDefaults) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cubby-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaultsName = "cubby-migration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: root)
        }
        try test(root.appendingPathComponent("accounts"), root.appendingPathComponent("default.store"), defaults)
    }

    @MainActor
    private func seed(_ local: LocalDataManager) throws -> InventoryArchive {
        let home = local.createHome(name: "Offline home")
        home.clientCreateID = nil
        home.icon = "archivebox"
        home.createdAt = Date(timeIntervalSince1970: 123456)
        home.sortOrder = 9
        let location = local.createLocation(homeId: home.id, name: "Deleted shelf", parentId: nil, type: "container")!
        location.clientCreateID = nil
        local.deleteLocation(location)
        let item = local.createItem(homeId: home.id, name: "Unsynced item", locationId: location.id)!
        item.clientCreateID = nil
        item.documentsData = Data("malformed-but-preserved-payload".utf8)
        item.propertiesData = Data([0, 1, 254])
        item.photoUrls = ["homes/legacy/items/photos/example.jpg"]
        item.notes = "Private synthetic note"
        item.quantity = 7
        item.sortOrder = 12
        item.estimatedValueCents = 456
        item.serialNumber = "SYNTHETIC"
        item.isFlagged = true
        local.deleteItem(item)
        let operation = SyncOperation(entityType: "item", entityId: item.id, operation: "delete", payload: Data([0, 255]))
        operation.failureCount = 3
        operation.lastError = "Synthetic retry"
        local.context!.insert(operation)
        // A relationship-free row must not disappear in an API-shaped export.
        local.context!.insert(LocalItem(homeId: "orphan", name: "Unlinked pending item"))
        try local.context!.save()
        return try InventoryArchive(context: local.context!)
    }

    @MainActor
    func testDiskMigrationPreservesEveryFieldAndKnownOwnerAcrossOtherAccountFirst() throws {
        try withDiskFixture { root, legacy, defaults in
            var local: LocalDataManager? = LocalDataManager(accountDefaults: defaults, storageRoot: root, legacyURL: legacy)
            let expected = try seed(local!)
            defaults.set("owner-a", forKey: LocalDataManager.accountOwnerKey)
            XCTAssertEqual(try local!.bindAccount(userID: "owner-b"), .allowed)
            XCTAssertTrue(local!.fetchHomes().isEmpty)
            XCTAssertFalse(try local!.hasLegacyRecovery(for: "owner-b"))
            XCTAssertThrowsError(try local!.recoveryData(for: "owner-b"))
            local = nil
            local = LocalDataManager(accountDefaults: defaults, storageRoot: root, legacyURL: legacy)
            XCTAssertEqual(try local!.bindAccount(userID: "owner-a"), .allowed)
            XCTAssertEqual(try InventoryArchive(context: local!.context!), expected)
            XCTAssertEqual(try JSONDecoder().decode(InventoryArchive.self, from: Data(contentsOf: root.appendingPathComponent("legacy-recovery.json"))), expected)
            local = nil
            local = LocalDataManager(accountDefaults: defaults, storageRoot: root, legacyURL: legacy)
            XCTAssertEqual(try local!.bindAccount(userID: "owner-a"), .allowed)
            XCTAssertEqual(try InventoryArchive(context: local!.context!), expected)
        }
    }

    @MainActor
    func testCrashRecoveryBeforeAndAfterAtomicPublicationNeverReplaysOrLosesData() throws {
        for checkpoint in [LocalDataManager.MigrationCheckpoint.archived, .imported, .published] {
            try withDiskFixture { root, legacy, defaults in
                var local: LocalDataManager? = LocalDataManager(accountDefaults: defaults, storageRoot: root, legacyURL: legacy)
                let expected = try seed(local!)
                local!.migrationCheckpoint = { if $0 == checkpoint { throw CocoaError(.fileWriteUnknown) } }
                XCTAssertThrowsError(try local!.bindAccount(userID: "owner-a", claimLegacy: true))
                XCTAssertNil(local!.boundAccountID)
                local = nil
                local = LocalDataManager(accountDefaults: defaults, storageRoot: root, legacyURL: legacy)
                let access = try local!.bindAccount(userID: "owner-a")
                if access == .claimRequired { XCTAssertEqual(try local!.bindAccount(userID: "owner-a", claimLegacy: true), .allowed) }
                XCTAssertEqual(try InventoryArchive(context: local!.context!), expected)
                XCTAssertEqual(try local!.bindAccount(userID: "owner-b"), .allowed)
                XCTAssertTrue(local!.fetchHomes().isEmpty)
                XCTAssertEqual(try local!.bindAccount(userID: "owner-a"), .allowed)
                XCTAssertEqual(try InventoryArchive(context: local!.context!), expected)
            }
        }
    }

    @MainActor
    func testCorruptCatalogFailsClosedWithoutCreatingOrClaimingStore() throws {
        try withDiskFixture { root, legacy, defaults in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("broken".utf8).write(to: root.appendingPathComponent("catalog.json"))
            let local = LocalDataManager(accountDefaults: defaults, storageRoot: root, legacyURL: legacy)
            XCTAssertThrowsError(try local.bindAccount(userID: "owner-a", claimLegacy: true))
            XCTAssertNil(local.context)
            XCTAssertNil(local.boundAccountID)
        }
    }
}


final class AccountMediaCacheTests: XCTestCase {
    @MainActor
    func testMediaCacheSeparatesAccountsOnDiskAndReopensOriginalAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cubby-media-\(UUID().uuidString)")
        let api = APIClient()
        defer { api.clearAuthTokens(); try? FileManager.default.removeItem(at: root) }
        var reads = 0
        let cache = RemotePhotoCache(root: root, fetch: { _ in
            reads += 1
            return Data([UInt8(reads)])
        })
        let url = URL(string: "https://synthetic.invalid/photo.jpg")!
        api.setAuthTokens(token: "synthetic-a", refreshToken: nil)
        try api.verifyLocalAccount("a", generation: api.sessionGeneration)
        let a = try await cache.data(for: url, scope: MediaAccountScope(api: api))
        api.setAuthTokens(token: "synthetic-b", refreshToken: nil)
        try api.verifyLocalAccount("b", generation: api.sessionGeneration)
        let b = try await cache.data(for: url, scope: MediaAccountScope(api: api))
        XCTAssertEqual(a, Data([1]))
        XCTAssertEqual(b, Data([2]))
        let reopened = RemotePhotoCache(root: root, fetch: { _ in XCTFail("Must use A's persisted cache"); return Data() })
        api.setAuthTokens(token: "synthetic-a2", refreshToken: nil)
        try api.verifyLocalAccount("a", generation: api.sessionGeneration)
        let restored = try await reopened.data(for: url, scope: MediaAccountScope(api: api))
        XCTAssertEqual(restored, a)
        XCTAssertEqual(reads, 2)
    }

    @MainActor
    func testLateMediaDownloadCannotPublishOrCacheAfterSwitch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cubby-media-late-\(UUID().uuidString)")
        let api = APIClient()
        defer { api.clearAuthTokens(); try? FileManager.default.removeItem(at: root) }
        let started = expectation(description: "download started")
        var response: CheckedContinuation<Data, Error>?
        let cache = RemotePhotoCache(root: root, fetch: { _ in
            try await withCheckedThrowingContinuation { continuation in
                response = continuation
                started.fulfill()
            }
        })
        api.setAuthTokens(token: "synthetic-a", refreshToken: nil)
        try api.verifyLocalAccount("a", generation: api.sessionGeneration)
        let scope = MediaAccountScope(api: api)
        let request = Task { try await cache.data(for: URL(string: "https://synthetic.invalid/late.jpg")!, scope: scope) }
        await fulfillment(of: [started], timeout: 3)
        api.setAuthTokens(token: "synthetic-b", refreshToken: nil)
        try api.verifyLocalAccount("b", generation: api.sessionGeneration)
        response?.resume(returning: Data([1]))
        do { _ = try await request.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
