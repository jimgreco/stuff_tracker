import SwiftUI
import AuthenticationServices
import GoogleSignIn

enum LoginViewMode: Equatable {
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
            Image("AppLaunchPhoto")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .accessibilityHidden(true)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.22),
                    Color.black.opacity(0.38),
                    Color.black.opacity(0.72),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 34) {
                        VStack(spacing: 14) {
                            CubbyBrandMark(size: 72)

                            VStack(spacing: 7) {
                                Text(mode.title)
                                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)

                                Text(mode == .initial ? "A place for everything." : "Reconnect your CubbyLog")
                                    .font(.headline.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.82))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .accessibilityElement(children: .combine)

                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 7) {
                                Label(
                                    mode == .initial ? "Start organizing" : "Your account is ready",
                                    systemImage: mode.icon
                                )
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(CubbyTheme.warmInk)

                                Text(mode.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(CubbyTheme.mutedInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            VStack(spacing: 12) {
                                GoogleSignInButton()
                                    .environmentObject(authStore)

                                SignInWithAppleButton(.signIn) { request in
                                    request.requestedScopes = [.fullName, .email]
                                } onCompletion: { result in
                                    handleApple(result)
                                }
                                .signInWithAppleButtonStyle(.black)
                                .authProviderButtonChrome(background: .black)
                                .disabled(authStore.isLoading)

                                #if DEBUG
                                LocalDevSignInButton()
                                    .environmentObject(authStore)
                                #endif
                            }

                            if let error = authStore.errorMessage {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(CubbyTheme.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(CubbyTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            Text("Your inventory stays private to your account and the people you invite.")
                                .font(.caption)
                                .foregroundStyle(CubbyTheme.mutedInk)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                        .cubbyPanel(padding: 20, cornerRadius: CubbyTheme.Radius.hero, elevated: true)
                        .frame(maxWidth: 520)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 32)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .allowsHitTesting(!authStore.isLoading)
                .accessibilityHidden(authStore.isLoading)
            }
        }
        .overlay {
            if authStore.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(CubbyTheme.green)
                    Text("Signing in…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(CubbyTheme.mutedInk)
                }
                .cubbyPanel(padding: 22, elevated: true)
                .frame(maxWidth: 220)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Signing in")
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
            .authProviderButtonChrome(background: CubbyTheme.greenSoft)
        }
        .foregroundStyle(CubbyTheme.warmInk)
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
            .authProviderButtonChrome(background: CubbyTheme.paper)
        }
        .foregroundStyle(CubbyTheme.warmInk)
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
    let background: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: AuthProviderButtonMetrics.cornerRadius,
            style: .continuous
        )

        content
            .frame(maxWidth: .infinity)
            .frame(height: AuthProviderButtonMetrics.height)
            .background(background, in: shape)
            .clipShape(shape)
            .overlay {
                shape
                    .stroke(CubbyTheme.floorBorder.opacity(0.86), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .shadow(color: CubbyTheme.shelfShadow.opacity(0.10), radius: 8, y: 4)
            .contentShape(shape)
    }
}

private extension View {
    func authProviderButtonChrome(background: Color = CubbyTheme.paper) -> some View {
        modifier(AuthProviderButtonChrome(background: background))
    }
}
