import SwiftUI
import AuthenticationServices
import GoogleSignIn

enum LoginViewMode {
    case initial
    case reconnect

    var icon: String {
        switch self {
        case .initial: return "archivebox.fill"
        case .reconnect: return "person.crop.circle.badge.exclamationmark"
        }
    }

    var title: String {
        switch self {
        case .initial: return "CubbyLog"
        case .reconnect: return "Sign In Required"
        }
    }

    var subtitle: String {
        switch self {
        case .initial: return "Know where everything is."
        case .reconnect: return "This device was signed in before. Sign in again to keep syncing."
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var authStore: AuthStore
    let mode: LoginViewMode

    init(mode: LoginViewMode = .initial) {
        self.mode = mode
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Logo / title
                VStack(spacing: 12) {
                    Image(systemName: mode.icon)
                        .font(.system(size: 64))
                    .foregroundStyle(.white)

                    Text(mode.title)
                        .font(.largeTitle.bold())

                    Text(mode.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // Sign-in buttons
                VStack(spacing: 16) {
                    GoogleSignInButton()
                        .environmentObject(authStore)

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleApple(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .authProviderButtonChrome()
                    .disabled(authStore.isLoading)

                    #if DEBUG
                    LocalDevSignInButton()
                        .environmentObject(authStore)
                    #endif
                }
                .padding(.horizontal, 32)

                if let error = authStore.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()
            }
        }
        .overlay {
            if authStore.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                Task { await authStore.signInWithApple(credential: credential) }
            }
        case .failure(let error):
            let nsError = error as NSError
            
            // Don't show error if user canceled
            if nsError.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            
            // Provide helpful error messages
            switch nsError.code {
            case ASAuthorizationError.unknown.rawValue:
                authStore.errorMessage = "Sign in with Apple failed. Make sure the capability is enabled and you're signed into iCloud."
            case ASAuthorizationError.invalidResponse.rawValue:
                authStore.errorMessage = "Invalid response from Apple. Please try again."
            case ASAuthorizationError.notHandled.rawValue:
                authStore.errorMessage = "Sign in request was not handled."
            case ASAuthorizationError.failed.rawValue:
                authStore.errorMessage = "Sign in with Apple failed. Please check your settings."
            default:
                authStore.errorMessage = "Error: \(error.localizedDescription) (Code: \(nsError.code))"
            }
        }
    }
}

#if DEBUG
struct LocalDevSignInButton: View {
    @EnvironmentObject var authStore: AuthStore
    var onSignedIn: (() -> Void)?

    var body: some View {
        Button {
            Task {
                await authStore.signInForLocalDevelopment()
                if authStore.isAuthenticated {
                    onSignedIn?()
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "hammer.circle.fill")
                    .font(.title3)
                Text("Dev Sign In")
                    .font(.body.weight(.medium))
            }
            .authProviderButtonChrome(background: Color(.secondarySystemBackground))
        }
        .foregroundStyle(.white)
        .disabled(authStore.isLoading)
        .buttonStyle(.plain)
    }
}
#endif

// MARK: - Google Sign-In Button

struct GoogleSignInButton: View {
    @EnvironmentObject var authStore: AuthStore

    var body: some View {
        Button {
            signInWithGoogle()
        } label: {
            HStack(spacing: 12) {
                Image("google_logo")
                    .resizable()
                    .frame(width: 20, height: 20)
                Text("Sign in with Google")
                    .font(.body.weight(.medium))
            }
            .authProviderButtonChrome()
        }
        .foregroundStyle(.white)
        .disabled(authStore.isLoading)
        .buttonStyle(.plain)
    }

    private func signInWithGoogle() {
        // Ensure configuration is set
        if GIDSignIn.sharedInstance.configuration == nil {
            // Try to get from Info.plist first
            let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
                ?? "YOUR_CLIENT_ID_HERE.apps.googleusercontent.com" // Replace this with your actual client ID
            
            if clientID.contains("YOUR_CLIENT_ID_HERE") {
                authStore.errorMessage = "Please replace the placeholder Google Client ID"
                return
            }
            
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first?.rootViewController else { 
                authStore.errorMessage = "Could not find root view controller"
                return 
            }

        // Use signIn with presenting view controller - this should handle passkeys
        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error {
                Task { @MainActor in
                    authStore.errorMessage = error.localizedDescription
                }
                return
            }
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else { 
                Task { @MainActor in
                    authStore.errorMessage = "Failed to get ID token from Google"
                }
                return 
            }
            Task { await authStore.signInWithGoogle(idToken: idToken) }
        }
    }
}

private enum AuthProviderButtonMetrics {
    static let height: CGFloat = 50
    static let cornerRadius: CGFloat = 10
}

private struct AuthProviderButtonChrome: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: AuthProviderButtonMetrics.cornerRadius,
            style: .continuous
        )

        content
            .frame(maxWidth: .infinity)
            .frame(height: AuthProviderButtonMetrics.height)
            .foregroundStyle(.white)
            .background {
                CubbyWoodButtonFill(shape: shape)
            }
            .clipShape(shape)
            .overlay {
                shape
                    .stroke(CubbyTheme.darkWoodBottom.opacity(0.85), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(shape)
    }
}

private extension View {
    func authProviderButtonChrome(background: Color = Color(.systemBackground)) -> some View {
        modifier(AuthProviderButtonChrome())
    }
}
