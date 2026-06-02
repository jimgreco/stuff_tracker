import SwiftUI
import AuthenticationServices
import GoogleSignIn
import StoreKit

struct AccountView: View {
    @ObservedObject var homeStore: HomeStore
    var onReplayTutorial: () -> Void = {}
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var syncManager: SyncManager
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var showMergeSheet = false
    @State private var serverHasData = false

    private var ownedHomes: [HomeDetail] {
        homeStore.homeDetails.filter { $0.role == "owner" || $0.role == "admin" }
    }

    private var appBuildText: String {
        AccountBuildInfoPresentation.text(info: Bundle.main.infoDictionary)
    }

    private static let fractionalISODateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoDateFormatter = ISO8601DateFormatter()

    var body: some View {
        NavigationStack {
            List {
                if authStore.isAuthenticated {
                    authenticatedSection
                } else {
                    unauthenticatedSection
                }

                tutorialSection
                    .cubbySheetRows()
                appBuildSection
                    .cubbySheetRows(prominence: 0.55)
            }
            .cubbySheetChrome()
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if authStore.isLoading || syncManager.isSyncing || subscriptionStore.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
            .sheet(isPresented: $showMergeSheet) {
                MergeChoiceView(
                    homeStore: homeStore,
                    serverHasData: serverHasData,
                    onCompleted: {
                        showMergeSheet = false
                        dismiss()
                    }
                )
                .environmentObject(syncManager)
            }
            .task(id: authStore.isAuthenticated) {
                if authStore.isAuthenticated {
                    await subscriptionStore.refresh()
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
        .listRowSeparator(.hidden)
    }

    private var tutorialSection: some View {
        Section("Tutorial") {
            Button {
                onReplayTutorial()
            } label: {
                Label("Reset Tutorial", systemImage: "arrow.counterclockwise.circle")
            }
        }
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
                            Circle().fill(CubbyTheme.greenSoft.opacity(0.72))
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                        .overlay {
                            Circle().stroke(CubbyTheme.floorBorder, lineWidth: 1)
                        }
                    } else {
                        Circle()
                            .fill(CubbyTheme.greenSoft.opacity(0.78))
                            .frame(width: 60, height: 60)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.title)
                                    .foregroundStyle(CubbyTheme.green)
                            }
                            .overlay {
                                Circle().stroke(CubbyTheme.floorBorder, lineWidth: 1)
                            }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.name)
                            .font(.headline)
                            .foregroundStyle(CubbyTheme.warmInk)
                        Text(user.email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .cubbySheetRows(prominence: 1.04)

        subscriptionSection

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
                        .foregroundStyle(CubbyTheme.green)
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

            if syncManager.deferredServerChangeCount > 0 {
                HStack {
                    Label("Server Changes Held", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(CubbyTheme.amber)
                    Spacer()
                    Text("\(syncManager.deferredServerChangeCount)")
                        .foregroundStyle(.secondary)
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
        .cubbySheetRows()

        if let error = subscriptionStore.errorMessage {
            Section("Subscription Error") {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .cubbySheetRows(prominence: 0.96)
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
        .cubbySheetRows()

        if let error = syncManager.syncError {
            Section("Error") {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .cubbySheetRows(prominence: 0.96)
        }

        Section {
            Button(role: .destructive) {
                Task {
                    await authStore.signOutEverywhere()
                    dismiss()
                }
            } label: {
                HStack {
                    Spacer()
                    Text("Sign Out Everywhere")
                    Spacer()
                }
            }

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
        .cubbySheetRows(prominence: 0.92)
    }

    @ViewBuilder
    private var subscriptionSection: some View {
        Section("Subscription") {
            if let plan = subscriptionStore.plan {
                HStack {
                    Text("Plan")
                    Spacer()
                    Label(plan.isPaid ? "Paid" : "Free", systemImage: plan.isPaid ? "checkmark.seal.fill" : "circle")
                        .foregroundStyle(plan.isPaid ? CubbyTheme.green : .secondary)
                }

                if !plan.isPaid {
                    quotaRow(
                        title: "Containers + Items",
                        used: plan.usage.totalContainersAndItems,
                        limit: plan.limits.totalContainersAndItems
                    )
                    quotaRow(title: "Images", used: plan.usage.images, limit: plan.limits.images)
                    quotaRow(title: "Documents", used: plan.usage.documents, limit: plan.limits.documents)

                    if subscriptionStore.products.isEmpty {
                        Text("Subscription products are not available.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(subscriptionStore.products, id: \.id) { product in
                            Button {
                                guard let userId = authStore.currentUser?.id else { return }
                                Task { await subscriptionStore.purchase(product, userId: userId) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(product.displayName)
                                            .foregroundStyle(.primary)
                                        if !product.description.isEmpty {
                                            Text(product.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    Text(product.displayPrice)
                                        .font(.body.weight(.semibold))
                                }
                            }
                            .disabled(subscriptionStore.isLoading)
                        }
                    }
                } else if let entitlement = plan.entitlement {
                    if let expiresAt = entitlement.expiresAt.flatMap(dateFromISOString) {
                        HStack {
                            Text("Renews")
                            Spacer()
                            Text(expiresAt, style: .date)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if entitlement.source != "app_store" {
                        HStack {
                            Text("Source")
                            Spacer()
                            Text(entitlement.source.capitalized)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    Task { await subscriptionStore.restorePurchases() }
                } label: {
                    HStack {
                        Spacer()
                        Text("Restore Purchases")
                        Spacer()
                    }
                }
                .disabled(subscriptionStore.isLoading)
            } else {
                HStack {
                    ProgressView()
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cubbySheetRows()
    }

    private func quotaRow(title: String, used: Int, limit: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(used)/\(limit)")
                .foregroundStyle(used >= limit ? CubbyTheme.amber : .secondary)
        }
    }

    private func dateFromISOString(_ value: String) -> Date? {
        Self.fractionalISODateFormatter.date(from: value) ?? Self.isoDateFormatter.date(from: value)
    }

    // MARK: - Unauthenticated

    @ViewBuilder
    private var unauthenticatedSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(CubbyTheme.green)
                    .padding(18)
                    .background(CubbyTheme.greenSoft.opacity(0.72), in: Circle())
                    .overlay {
                        Circle().stroke(CubbyTheme.floorBorder, lineWidth: 1)
                    }
                    .padding(.top, 20)

                Text("Sign in to sync your data")
                    .font(.headline)
                    .foregroundStyle(CubbyTheme.warmInk)

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
        .listRowBackground(CubbySheetRowBackground(prominence: 1.04))

        if let error = authStore.errorMessage {
            Section {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .cubbySheetRows(prominence: 0.96)
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
                dismiss()
            } else {
                // Only server data (or neither) — pull from server
                await syncManager.replaceLocalWithServer()
                homeStore.reloadFromLocal()
                dismiss()
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

enum AccountBuildInfoPresentation {
    static func text(info: [String: Any]?) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? "Unknown"
        let gitHash = info?["GitCommitHash"] as? String ?? "Unknown"
        return "Version \(version) (\(build)) - \(gitHash)"
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
                Image("google_logo")
                    .resizable()
                    .frame(width: 20, height: 20)
                Text("Sign in with Google")
                    .font(.body.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(CubbyTheme.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(CubbyTheme.floorBorder.opacity(0.78), lineWidth: 1)
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
            Task {
                await authStore.signInWithGoogle(idToken: idToken)
                await MainActor.run {
                    onSignedIn()
                }
            }
        }
    }
}

// MARK: - Merge Choice View (shown when both local and server have data)

struct MergeChoiceView: View {
    @ObservedObject var homeStore: HomeStore
    let serverHasData: Bool
    let onCompleted: () -> Void
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 48))
                    .foregroundStyle(CubbyTheme.green)
                    .padding(18)
                    .background(CubbyTheme.greenSoft.opacity(0.72), in: Circle())
                    .overlay {
                        Circle().stroke(CubbyTheme.floorBorder, lineWidth: 1)
                    }
                    .padding(.top, 40)

                Text("You have data on both this device and the server")
                    .font(.headline)
                    .foregroundStyle(CubbyTheme.warmInk)
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
                            onCompleted()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text("Merge Both")
                                .font(.headline)
                            Text("Combine local and server data")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(CubbyTheme.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        Task {
                            await syncManager.uploadLocalToServer()
                            homeStore.reloadFromLocal()
                            dismiss()
                            onCompleted()
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
                        .background(CubbyTheme.paper)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(CubbyTheme.floorBorder.opacity(0.78), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        Task {
                            await syncManager.replaceLocalWithServer()
                            homeStore.reloadFromLocal()
                            dismiss()
                            onCompleted()
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
                        .background(CubbyTheme.paper)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(CubbyTheme.floorBorder.opacity(0.78), lineWidth: 1)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CubbySheetBackground())
            .navigationTitle("Sync Data")
            .navigationBarTitleDisplayMode(.inline)
            .cubbyNavigationBarChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
