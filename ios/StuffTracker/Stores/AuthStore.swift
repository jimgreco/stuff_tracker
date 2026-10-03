import SwiftUI
import AuthenticationServices

@MainActor
final class AuthStore: ObservableObject {
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var isRestoringSession = false
    @Published private(set) var hasCompletedAuthentication: Bool
    @Published var errorMessage: String?
    @Published private(set) var pendingInventoryClaim: User?
    private var pendingResponse: AuthResponse?
    private var pendingGeneration: UUID?
    private let api: APIClient
    private let local: LocalDataManager

    var isAuthenticated: Bool { currentUser != nil }
    var requiresSignIn: Bool {
        Self.shouldRequireSignIn(
            hasCompletedAuthentication: hasCompletedAuthentication,
            hasStoredSession: Self.hasStoredSession,
            isAuthenticated: isAuthenticated,
            isRestoringSession: isRestoringSession
        )
    }

    nonisolated static let completedAuthenticationDefaultsKey = "has_completed_authentication"

    init(api: APIClient = .shared, local: LocalDataManager? = nil, restoreSession: Bool = true) {
        self.api = api
        self.local = local ?? .shared
        #if DEBUG
        ScreenshotSeedData.prepareAuthenticationStateIfNeeded()
        #endif

        let hasStoredSession = Self.hasStoredSession
        if hasStoredSession {
            Self.markAuthenticationCompleted()
        }
        hasCompletedAuthentication = Self.hasCompletedAuthentication

        // Restore session if a current or migrated token exists.
        if hasStoredSession && restoreSession {
            isRestoringSession = true
            Task { await restoreStoredSession() }
        }
    }

    nonisolated static var hasStoredSession: Bool {
        APIClient.shared.hasToken
    }

    nonisolated static var hasCompletedAuthentication: Bool {
        UserDefaults.standard.bool(forKey: completedAuthenticationDefaultsKey)
    }

    nonisolated static func markAuthenticationCompleted() {
        UserDefaults.standard.set(true, forKey: completedAuthenticationDefaultsKey)
    }

    nonisolated static func shouldRequireSignIn(
        hasCompletedAuthentication: Bool,
        hasStoredSession: Bool,
        isAuthenticated: Bool,
        isRestoringSession: Bool
    ) -> Bool {
        (hasCompletedAuthentication || hasStoredSession) && !isAuthenticated && !isRestoringSession
    }

    nonisolated static func shouldClearStoredSession(after error: Error) -> Bool {
        guard case APIError.httpError(let status, _) = error else {
            return false
        }
        return status == 401 || status == 404
    }

    func signInWithGoogle(idToken: String) async {
        isLoading = true
        let generation = api.sessionGeneration
        defer { isLoading = false }
        do {
            errorMessage = nil
            let resp = try await api.signInWithGoogle(idToken: idToken)
            try api.requireCurrentSession(generation)
            try acceptVerifiedUser(resp.user, response: resp)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    func signInForLocalDevelopment() async {
        isLoading = true
        let generation = api.sessionGeneration
        defer { isLoading = false }
        do {
            errorMessage = nil
            let resp = try await api.signInForLocalDevelopment()
            try api.requireCurrentSession(generation)
            try acceptVerifiedUser(resp.user, response: resp)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    #endif

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            errorMessage = "Failed to read Apple identity token"
            return
        }
        isLoading = true
        let generation = api.sessionGeneration
        defer { isLoading = false }
        do {
            errorMessage = nil
            let resp = try await api.signInWithApple(
                identityToken: identityToken,
                fullName: credential.fullName
            )
            try api.requireCurrentSession(generation)
            try acceptVerifiedUser(resp.user, response: resp)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        api.clearAuthTokens()
        currentUser = nil
        pendingInventoryClaim = nil
        pendingResponse = nil
        pendingGeneration = nil
    }

    func signOutEverywhere() async {
        isLoading = true
        let generation = api.sessionGeneration
        defer { isLoading = false }
        do {
            errorMessage = nil
            try await api.logoutAll()
            try api.requireCurrentSession(generation)
            signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // A verified identity may only open its retained store. Legacy inventory has
    // no trustworthy owner field: preserve it and ask, never infer from home owners.
    func acceptVerifiedUser(_ user: User, response: AuthResponse? = nil) throws {
        Self.markAuthenticationCompleted()
        hasCompletedAuthentication = true
        currentUser = nil
        pendingInventoryClaim = nil
        pendingResponse = nil
        pendingGeneration = nil
        switch try local.bindAccount(userID: user.id) {
        case .allowed:
            try activate(user, response: response)
        case .claimRequired:
            pendingInventoryClaim = user
            pendingResponse = response
            pendingGeneration = api.sessionGeneration
        case .differentAccount:
            api.clearAuthTokens()
            errorMessage = "This device has inventory saved for another account. Sign in with that account to access it. Your saved inventory and unsynced changes have been preserved."
        }
    }

    func confirmInventoryClaim() {
        guard let user = pendingInventoryClaim, let generation = pendingGeneration else { return }
        do {
            try api.requireCurrentSession(generation)
            guard try local.bindAccount(userID: user.id, claimLegacy: true) == .allowed else {
                throw CocoaError(.fileReadNoPermission)
            }
            try activate(user, response: pendingResponse)
            pendingInventoryClaim = nil
            pendingResponse = nil
            pendingGeneration = nil
        } catch {
            errorMessage = "Could not open the saved inventory. Sign in again. Your local data is unchanged."
        }
    }

    private func activate(_ user: User, response: AuthResponse?) throws {
        if let response {
            api.setAuthTokens(token: response.token, refreshToken: response.refreshToken)
        }
        try api.verifyLocalAccount(user.id, generation: api.sessionGeneration)
        currentUser = user
        errorMessage = nil
    }

    func restoreStoredSession() async {
        isRestoringSession = true
        let generation = api.sessionGeneration
        defer { isRestoringSession = false }

        do {
            let user: User = try await api.request("GET", path: "/auth/me")
            try api.requireCurrentSession(generation)
            try acceptVerifiedUser(user)
        } catch {
            guard (try? api.requireCurrentSession(generation)) != nil else { return }
            if Self.shouldClearStoredSession(after: error) {
                api.clearAuthTokens()
                errorMessage = "Your session expired. Sign in again to keep syncing."
            } else {
                errorMessage = "Could not verify your account. Reconnect and sign in again. Your saved inventory is unchanged."
            }
        }
    }
}
