import Foundation
import SwiftUI
import SwiftData
import GoogleSignIn

struct ItemDeepLink: Identifiable, Equatable {
    static let universalScheme = "https"
    static let universalHost = "cubbylog.com"
    static let supportedUniversalHosts = [
        "cubbylog.com",
        "www.cubbylog.com",
    ]
    static let universalPathPrefix = "items"

    let homeId: String
    let itemId: String

    var id: String {
        "\(homeId):\(itemId)"
    }

    static func itemAnchorID(_ itemId: String) -> String {
        "item:\(itemId)"
    }

    var url: URL {
        universalURL
    }

    var universalURL: URL {
        var url = URL(string: "\(Self.universalScheme)://\(Self.universalHost)")!
        url.appendPathComponent(Self.universalPathPrefix)
        url.appendPathComponent(homeId)
        url.appendPathComponent(itemId)
        return url
    }

    init(homeId: String, itemId: String) {
        self.homeId = homeId
        self.itemId = itemId
    }

    init?(url: URL) {
        if let link = Self.parseUniversalLink(url) {
            self = link
            return
        }

        return nil
    }

    private static func parseUniversalLink(_ url: URL) -> ItemDeepLink? {
        guard url.scheme?.lowercased() == Self.universalScheme,
              let host = url.host?.lowercased(),
              Self.supportedUniversalHosts.contains(host) else {
            return nil
        }

        let parts = url.pathComponents
            .filter { $0 != "/" }
            .map { $0.removingPercentEncoding ?? $0 }

        guard parts.count == 3,
              parts[0] == Self.universalPathPrefix,
              !parts[1].isEmpty,
              !parts[2].isEmpty else {
            return nil
        }

        return ItemDeepLink(homeId: parts[1], itemId: parts[2])
    }
}

@MainActor
final class DeepLinkStore: ObservableObject {
    @Published var pendingItemLink: ItemDeepLink?

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let link = ItemDeepLink(url: url) else { return false }
        pendingItemLink = link
        return true
    }

    func clear(_ link: ItemDeepLink) {
        guard pendingItemLink == link else { return }
        pendingItemLink = nil
    }
}

@main
struct StuffTrackerApp: App {
    @StateObject private var authStore = AuthStore()
    @StateObject private var syncManager = SyncManager.shared
    @StateObject private var subscriptionStore = SubscriptionStore.shared
    @StateObject private var tutorialController = FirstRunTutorialController()
    @StateObject private var deepLinkStore = DeepLinkStore()

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
                .tint(CubbyTheme.green)
                .environmentObject(authStore)
                .environmentObject(syncManager)
                .environmentObject(subscriptionStore)
                .environmentObject(tutorialController)
                .environmentObject(deepLinkStore)
                .onOpenURL { url in
                    if !GIDSignIn.sharedInstance.handle(url) {
                        deepLinkStore.handle(url)
                    }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL {
                        deepLinkStore.handle(url)
                    }
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
