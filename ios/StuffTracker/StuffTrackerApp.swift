import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct StuffTrackerApp: App {
    @StateObject private var authStore = AuthStore()
    @StateObject private var syncManager = SyncManager.shared
    @StateObject private var subscriptionStore = SubscriptionStore.shared
    @StateObject private var tutorialController = FirstRunTutorialController()

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
                .environmentObject(subscriptionStore)
                .environmentObject(tutorialController)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .task {
                    // Sync when app launches if authenticated
                    if authStore.isAuthenticated {
                        await subscriptionStore.refresh()
                        await syncManager.performFullSync()
                    }
                }
        }
    }
}
