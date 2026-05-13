import SwiftUI
import AuthenticationServices

@MainActor
final class AuthStore: ObservableObject {
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?

    var isAuthenticated: Bool { currentUser != nil }

    init() {
        // Restore session if token exists
        if UserDefaults.standard.string(forKey: "jwt_token") != nil {
            Task { await fetchCurrentUser() }
        }
    }

    func signInWithGoogle(idToken: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            errorMessage = nil
            let resp = try await APIClient.shared.signInWithGoogle(idToken: idToken)
            APIClient.shared.setToken(resp.token)
            currentUser = resp.user
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
            APIClient.shared.setToken(resp.token)
            currentUser = resp.user
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
            APIClient.shared.setToken(resp.token)
            currentUser = resp.user
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        APIClient.shared.setToken(nil)
        currentUser = nil
    }

    private func fetchCurrentUser() async {
        do {
            let user: User = try await APIClient.shared.request("GET", path: "/auth/me")
            currentUser = user
        } catch {
            // Token invalid/expired — clear it
            APIClient.shared.setToken(nil)
        }
    }
}
