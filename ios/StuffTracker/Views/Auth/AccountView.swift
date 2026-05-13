import SwiftUI
import AuthenticationServices
import GoogleSignIn

struct AccountView: View {
    @ObservedObject var homeStore: HomeStore
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss
    @State private var showMergeSheet = false
    @State private var serverHasData = false
    @State private var wasAuthenticated = false

    private var ownedHomes: [HomeDetail] {
        homeStore.homeDetails.filter { $0.role == "owner" || $0.role == "admin" }
    }

    private var appBuildText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? "Unknown"
        let gitHash = info?["GitCommitHash"] as? String ?? "Unknown"
        return "Version \(version) (\(build)) - \(gitHash)"
    }

    var body: some View {
        NavigationStack {
            List {
                if authStore.isAuthenticated {
                    authenticatedSection
                } else {
                    unauthenticatedSection
                }

                appBuildSection
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if authStore.isLoading || syncManager.isSyncing {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .sheet(isPresented: $showMergeSheet) {
                MergeChoiceView(
                    homeStore: homeStore,
                    serverHasData: serverHasData
                )
                .environmentObject(syncManager)
            }
            .onAppear { wasAuthenticated = authStore.isAuthenticated }
            .onChange(of: authStore.isAuthenticated) { _, isAuth in
                // Auto-dismiss after successful sign-in (but not on sign-out)
                if isAuth && !wasAuthenticated {
                    // Small delay so handlePostSignIn can run first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var appBuildSection: some View {
        Section {
            Text(appBuildText)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .textSelection(.enabled)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Authenticated

    @ViewBuilder
    private var authenticatedSection: some View {
        Section {
            if let user = authStore.currentUser {
                HStack(spacing: 12) {
                    if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(Color.gray.opacity(0.3))
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 60)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.title)
                                    .foregroundStyle(.white)
                            }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.name).font(.headline)
                        Text(user.email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
        }

        Section("Sync") {
            HStack {
                Text("Status")
                Spacer()
                if syncManager.isSyncing {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Syncing...").foregroundStyle(.secondary)
                    }
                } else {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if let lastSync = syncManager.lastSyncDate {
                HStack {
                    Text("Last Synced")
                    Spacer()
                    Text(lastSync, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }

            if syncManager.pendingSyncCount > 0 {
                NavigationLink {
                    PendingChangesView(homeStore: homeStore)
                } label: {
                    HStack {
                        Text("Pending Changes")
                        Spacer()
                        Text("\(syncManager.pendingSyncCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                Task {
                    await syncManager.performFullSync()
                    homeStore.reloadFromLocal()
                }
            } label: {
                HStack {
                    Spacer()
                    Text("Sync Now")
                    Spacer()
                }
            }
            .disabled(syncManager.isSyncing)
        }

        Section("Sharing") {
            if ownedHomes.isEmpty {
                Text("No homes to share")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                NavigationLink {
                    SharingView(homes: ownedHomes)
                } label: {
                    Label("Manage Sharing", systemImage: "person.2")
                }
            }
        }

        if let error = syncManager.syncError {
            Section("Error") {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }

        Section {
            Button(role: .destructive) {
                authStore.signOut()
                dismiss()
            } label: {
                HStack {
                    Spacer()
                    Text("Sign Out")
                    Spacer()
                }
            }
        }
    }

    // MARK: - Unauthenticated

    @ViewBuilder
    private var unauthenticatedSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .padding(.top, 20)

                Text("Sign in to sync your data")
                    .font(.headline)

                Text("Your data is saved locally. Sign in to sync across devices and share with others.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    GoogleSignInButtonCompact(onSignedIn: handlePostSignIn)

                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        handleApple(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(10)

                    #if DEBUG
                    LocalDevSignInButton(onSignedIn: handlePostSignIn)
                        .environmentObject(authStore)
                    #endif
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)

        if let error = authStore.errorMessage {
            Section {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Post sign-in handling

    private func handlePostSignIn() {
        guard authStore.isAuthenticated else { return }

        let hasLocalData = !LocalDataManager.shared.fetchHomes().isEmpty

        Task {
            // Check if server has data
            let hasServer: Bool
            do {
                let serverHomes: [Home] = try await APIClient.shared.listHomes()
                hasServer = !serverHomes.isEmpty
            } catch {
                hasServer = false
            }

            if hasLocalData && hasServer {
                // Both have data — ask user
                serverHasData = true
                showMergeSheet = true
            } else if hasLocalData && !hasServer {
                // Only local data — upload it
                await syncManager.uploadLocalToServer()
                homeStore.reloadFromLocal()
            } else {
                // Only server data (or neither) — pull from server
                await syncManager.replaceLocalWithServer()
                homeStore.reloadFromLocal()
            }
        }
    }

    // MARK: - Apple Sign In

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                Task {
                    await authStore.signInWithApple(credential: credential)
                    handlePostSignIn()
                }
            }
        case .failure(let error):
            let nsError = error as NSError
            if nsError.code == ASAuthorizationError.canceled.rawValue { return }
            authStore.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Google Sign-In Button

struct GoogleSignInButtonCompact: View {
    @EnvironmentObject var authStore: AuthStore
    var onSignedIn: () -> Void

    var body: some View {
        Button {
            signInWithGoogle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "g.circle.fill")
                    .font(.title3)
                Text("Sign in with Google")
                    .font(.body.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.separator), lineWidth: 1)
            )
            .cornerRadius(10)
        }
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
    }

    private func signInWithGoogle() {
        if GIDSignIn.sharedInstance.configuration == nil {
            let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
                ?? "YOUR_CLIENT_ID_HERE.apps.googleusercontent.com"
            if clientID.contains("YOUR_CLIENT_ID_HERE") {
                authStore.errorMessage = "Please configure Google Sign-In"
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

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { result, error in
            if let error {
                authStore.errorMessage = error.localizedDescription
                return
            }
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                authStore.errorMessage = "Failed to get ID token from Google"
                return
            }
            Task {
                await authStore.signInWithGoogle(idToken: idToken)
                onSignedIn()
            }
        }
    }
}

// MARK: - Merge Choice View (shown when both local and server have data)

struct MergeChoiceView: View {
    @ObservedObject var homeStore: HomeStore
    let serverHasData: Bool
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .padding(.top, 40)

                Text("You have data on both this device and the server")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text("How would you like to handle this?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    Button {
                        Task {
                            await syncManager.mergeLocalAndServer()
                            homeStore.reloadFromLocal()
                            dismiss()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text("Merge Both")
                                .font(.headline)
                            Text("Combine local and server data")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        Task {
                            await syncManager.uploadLocalToServer()
                            homeStore.reloadFromLocal()
                            dismiss()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text("Keep Local")
                                .font(.headline)
                            Text("Upload device data, overwrite server")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        Task {
                            await syncManager.replaceLocalWithServer()
                            homeStore.reloadFromLocal()
                            dismiss()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text("Keep Server")
                                .font(.headline)
                            Text("Replace device data with server data")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .navigationTitle("Sync Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
