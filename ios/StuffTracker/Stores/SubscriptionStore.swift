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
            return
        }

        let generation = api.sessionGeneration
        isLoading = true
        defer { if (try? api.requireCurrentSession(generation)) != nil { isLoading = false } }

        do {
            errorMessage = nil
            let nextPlan = try await api.getAccountPlan()
            try api.requireCurrentSession(generation)
            plan = nextPlan
            try await loadProducts()
            try api.requireCurrentSession(generation)
            await syncCurrentEntitlements()
        } catch {
            guard (try? api.requireCurrentSession(generation)) != nil else { return }
            errorMessage = error.localizedDescription
        }
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
                let nextPlan = try await api.syncAppStoreTransaction(signedTransactionInfo: verification.jwsRepresentation)
                try api.requireCurrentSession(generation)
                plan = nextPlan
                await transaction.finish()
            case .pending, .userCancelled:
                return
            @unknown default:
                return
            }
        } catch {
            guard (try? api.requireCurrentSession(generation)) != nil else { return }
            errorMessage = error.localizedDescription
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
            guard (try? api.requireCurrentSession(generation)) != nil else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func loadProducts() async throws {
        let generation = api.sessionGeneration
        let productIds: [String]
        do {
            productIds = try await api.getSubscriptionProductIds()
        } catch {
            try api.requireCurrentSession(generation)
            productIds = fallbackProductIds
        }

        let nextProducts = try await Product.products(for: productIds)
            .sorted { lhs, rhs in
                if lhs.subscription?.subscriptionPeriod.unit == rhs.subscription?.subscriptionPeriod.unit {
                    return lhs.price < rhs.price
                }
                return subscriptionSortRank(lhs) < subscriptionSortRank(rhs)
            }
        try api.requireCurrentSession(generation)
        products = nextProducts
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
            guard (try? api.requireCurrentSession(generation)) != nil else { return }
            errorMessage = error.localizedDescription
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
                guard (try? api.requireCurrentSession(generation)) != nil else { continue }
                errorMessage = error.localizedDescription
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
