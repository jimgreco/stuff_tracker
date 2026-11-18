import Foundation
import StoreKit
import Combine

@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    @Published private(set) var plan: AccountPlan?
    @Published private(set) var products: [Product] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// True once a product request finished without any purchasable products
    /// (StoreKit unavailable, agreements pending, network loss). The UI offers
    /// a retry instead of showing a raw error.
    @Published private(set) var productsUnavailable = false

    private let api: APIClient
    private var accountObserver: AnyCancellable?
    private let fallbackProductIds = [
        "com.jimgreco.stufftracker.pro.monthly",
        "com.jimgreco.stufftracker.pro.yearly"
    ]
    private var transactionUpdatesTask: Task<Void, Never>?

    init(api: APIClient = .shared, local: LocalDataManager? = nil, listenForUpdates: Bool = true) {
        self.api = api
        accountObserver = (local ?? .shared).$storeGeneration.sink { [weak self] _ in
            self?.plan = nil
            self?.errorMessage = nil
            self?.productsUnavailable = false
            self?.isLoading = false
        }
        if listenForUpdates { transactionUpdatesTask = Task { await listenForTransactionUpdates() } }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func refresh() async {
        guard api.hasToken, api.localAccountID != nil else {
            plan = nil
            products = []
            productsUnavailable = false
            return
        }

        let generation = api.sessionGeneration
        isLoading = true
        defer { if (try? api.requireCurrentSession(generation)) != nil { isLoading = false } }

        errorMessage = nil
        // Products load independently of the plan so a slow or failing plan
        // request never hides the purchase options, and vice versa.
        async let productsLoaded: Void = loadProducts(generation: generation)

        do {
            let nextPlan = try await api.getAccountPlan()
            try api.requireCurrentSession(generation)
            plan = nextPlan
        } catch {
            if (try? api.requireCurrentSession(generation)) != nil {
                errorMessage = "Couldn't load your plan. Check your connection and try again."
            }
        }

        await productsLoaded
        guard (try? api.requireCurrentSession(generation)) != nil else { return }
        await syncCurrentEntitlements()
    }

    func purchase(_ product: Product, userId: String) async {
        guard api.localAccountID == userId else { return }
        let generation = api.sessionGeneration
        isLoading = true
        defer { if (try? api.requireCurrentSession(generation)) != nil { isLoading = false } }

        do {
            errorMessage = nil
            let result = try await product.purchase(options: purchaseOptions(userId: userId))
            try api.requireCurrentSession(generation)
            switch result {
            case .success(let verification):
                let transaction = try verifiedTransaction(from: verification)
                do {
                    let nextPlan = try await api.syncAppStoreTransaction(signedTransactionInfo: verification.jwsRepresentation)
                    try api.requireCurrentSession(generation)
                    plan = nextPlan
                    await transaction.finish()
                } catch {
                    // StoreKit charged the user; leave the transaction unfinished so
                    // Transaction.updates and the next refresh deliver it again.
                    guard (try? api.requireCurrentSession(generation)) != nil else { return }
                    errorMessage = "Your purchase went through, but CubbyLog couldn't confirm it yet. It will update automatically, or tap Restore Purchases."
                }
            case .pending, .userCancelled:
                return
            @unknown default:
                return
            }
        } catch {
            guard (try? api.requireCurrentSession(generation)) != nil, !Self.isUserCancellation(error) else { return }
            errorMessage = "The purchase couldn't be completed. Please try again."
        }
    }

    func restorePurchases() async {
        guard api.localAccountID != nil else { return }
        let generation = api.sessionGeneration
        isLoading = true
        defer { if (try? api.requireCurrentSession(generation)) != nil { isLoading = false } }

        do {
            errorMessage = nil
            try await AppStore.sync()
            try api.requireCurrentSession(generation)
            await syncCurrentEntitlements()
            try api.requireCurrentSession(generation)
            let nextPlan = try await api.getAccountPlan()
            try api.requireCurrentSession(generation)
            plan = nextPlan
        } catch {
            guard (try? api.requireCurrentSession(generation)) != nil, !Self.isUserCancellation(error) else { return }
            errorMessage = "Couldn't restore purchases. Check your connection and try again."
        }
    }

    nonisolated static func isUserCancellation(_ error: Error) -> Bool {
        if case StoreKitError.userCancelled = error { return true }
        return error is CancellationError
    }

    private func loadProducts(generation: UUID) async {
        var productIds = (try? await api.getSubscriptionProductIds()) ?? []
        if productIds.isEmpty { productIds = fallbackProductIds }

        var nextProducts = (try? await Product.products(for: productIds)) ?? []
        if nextProducts.isEmpty, Set(productIds) != Set(fallbackProductIds) {
            nextProducts = (try? await Product.products(for: fallbackProductIds)) ?? []
        }
        guard (try? api.requireCurrentSession(generation)) != nil else { return }

        if !nextProducts.isEmpty || products.isEmpty {
            products = nextProducts.sorted { lhs, rhs in
                if lhs.subscription?.subscriptionPeriod.unit == rhs.subscription?.subscriptionPeriod.unit {
                    return lhs.price < rhs.price
                }
                return subscriptionSortRank(lhs) < subscriptionSortRank(rhs)
            }
        }
        productsUnavailable = products.isEmpty
    }

    private func syncCurrentEntitlements() async {
        guard api.hasToken, api.localAccountID != nil else { return }

        let generation = api.sessionGeneration
        do {
            for await result in Transaction.currentEntitlements {
                try api.requireCurrentSession(generation)
                guard case .verified(let transaction) = result,
                      productIdsForSync.contains(transaction.productID) else {
                    continue
                }
                let nextPlan = try await api.syncAppStoreTransaction(signedTransactionInfo: result.jwsRepresentation)
                try api.requireCurrentSession(generation)
                plan = nextPlan
            }
        } catch {
            // Background entitlement sync is retried on the next refresh and by
            // Transaction.updates; it must not surface an error on the
            // subscription screen the user did not act on.
        }
    }

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result,
                  productIdsForSync.contains(transaction.productID),
                  api.hasToken, api.localAccountID != nil else {
                continue
            }

            let generation = api.sessionGeneration
            do {
                let nextPlan = try await api.syncAppStoreTransaction(signedTransactionInfo: result.jwsRepresentation)
                try api.requireCurrentSession(generation)
                plan = nextPlan
                await transaction.finish()
            } catch {
                // Left unfinished so StoreKit redelivers it; retried silently.
                continue
            }
        }
    }

    private var productIdsForSync: Set<String> {
        Set(products.map(\.id)).union(fallbackProductIds)
    }

    private func purchaseOptions(userId: String) -> Set<Product.PurchaseOption> {
        guard let uuid = UUID(uuidString: userId) else {
            return []
        }
        return [.appAccountToken(uuid)]
    }

    private func verifiedTransaction(from result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            throw error
        }
    }

    private func subscriptionSortRank(_ product: Product) -> Int {
        guard let period = product.subscription?.subscriptionPeriod else {
            return 99
        }

        switch period.unit {
        case .month:
            return 0
        case .year:
            return 1
        case .week:
            return 2
        case .day:
            return 3
        @unknown default:
            return 99
        }
    }
}
