import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct StuffTrackerApp: App {
    @StateObject private var authStore = AuthStore()
    @StateObject private var syncManager = SyncManager.shared

    init() {
        // Configure Google Sign-In with client ID from Info.plist
        if let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String {
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config
        }
        
        // Initialize local data manager
        _ = LocalDataManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authStore)
                .environmentObject(syncManager)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .task {
                    // Sync when app launches if authenticated
                    if authStore.isAuthenticated {
                        await syncManager.performFullSync()
                    }
                }
        }
    }
}
