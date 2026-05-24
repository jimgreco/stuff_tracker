import SwiftUI
import AuthenticationServices

@MainActor
final class AuthStore: ObservableObject {
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var isRestoringSession = false
    @Published private(set) var hasCompletedAuthentication: Bool
    @Published var errorMessage: String?

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

    init() {
        let hasStoredSession = Self.hasStoredSession
        if hasStoredSession {
            Self.markAuthenticationCompleted()
        }
        hasCompletedAuthentication = Self.hasCompletedAuthentication

        // Restore session if a current or migrated token exists.
        if hasStoredSession {
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
        hasCompletedAuthentication && !hasStoredSession && !isAuthenticated && !isRestoringSession
    }

    nonisolated static func shouldClearStoredSession(after error: Error) -> Bool {
        guard case APIError.httpError(let status, _) = error else {
            return false
        }
        return status == 401 || status == 404
    }

    func signInWithGoogle(idToken: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            errorMessage = nil
            let resp = try await APIClient.shared.signInWithGoogle(idToken: idToken)
            completeSignIn(with: resp)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    func signInForLocalDevelopment() async {
        isLoading = true
        defer { isLoading = false }
        do {
            errorMessage = nil
            let resp = try await APIClient.shared.signInForLocalDevelopment()
            completeSignIn(with: resp)
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
        defer { isLoading = false }
        do {
            errorMessage = nil
            let resp = try await APIClient.shared.signInWithApple(
                identityToken: identityToken,
                fullName: credential.fullName
            )
            completeSignIn(with: resp)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        APIClient.shared.setToken(nil)
        currentUser = nil
    }

    func signOutEverywhere() async {
        isLoading = true
        defer { isLoading = false }
        do {
            errorMessage = nil
            try await APIClient.shared.logoutAll()
            signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func completeSignIn(with response: AuthResponse) {
        APIClient.shared.setToken(response.token)
        Self.markAuthenticationCompleted()
        hasCompletedAuthentication = true
        currentUser = response.user
    }

    private func restoreStoredSession() async {
        isRestoringSession = true
        defer { isRestoringSession = false }

        do {
            let user: User = try await APIClient.shared.request("GET", path: "/auth/me")
            Self.markAuthenticationCompleted()
            hasCompletedAuthentication = true
            currentUser = user
            errorMessage = nil
        } catch {
            if Self.shouldClearStoredSession(after: error) {
                APIClient.shared.setToken(nil)
                errorMessage = "Your session expired. Sign in again to keep syncing."
            }
        }
    }
}
