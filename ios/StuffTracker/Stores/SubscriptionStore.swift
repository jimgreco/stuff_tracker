import Foundation
import StoreKit

@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    @Published private(set) var plan: AccountPlan?
    @Published private(set) var products: [Product] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = APIClient.shared
    private let fallbackProductIds = [
        "com.jimgreco.stufftracker.pro.monthly",
        "com.jimgreco.stufftracker.pro.yearly"
    ]
    private var transactionUpdatesTask: Task<Void, Never>?

    private init() {
        transactionUpdatesTask = Task { await listenForTransactionUpdates() }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func refresh() async {
        guard api.hasToken else {
            plan = nil
            products = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            errorMessage = nil
            plan = try await api.getAccountPlan()
            try await loadProducts()
            await syncCurrentEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func purchase(_ product: Product, userId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            errorMessage = nil
            let result = try await product.purchase(options: purchaseOptions(userId: userId))
            switch result {
            case .success(let verification):
                let transaction = try verifiedTransaction(from: verification)
                plan = try await api.syncAppStoreTransaction(signedTransactionInfo: verification.jwsRepresentation)
                await transaction.finish()
            case .pending, .userCancelled:
                return
            @unknown default:
                return
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }

        do {
            errorMessage = nil
            try await AppStore.sync()
            await syncCurrentEntitlements()
            plan = try await api.getAccountPlan()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadProducts() async throws {
        let productIds: [String]
        do {
            productIds = try await api.getSubscriptionProductIds()
        } catch {
            productIds = fallbackProductIds
        }

        products = try await Product.products(for: productIds)
            .sorted { lhs, rhs in
                if lhs.subscription?.subscriptionPeriod.unit == rhs.subscription?.subscriptionPeriod.unit {
                    return lhs.price < rhs.price
                }
                return subscriptionSortRank(lhs) < subscriptionSortRank(rhs)
            }
    }

    private func syncCurrentEntitlements() async {
        guard api.hasToken else { return }

        do {
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result,
                      productIdsForSync.contains(transaction.productID) else {
                    continue
                }
                plan = try await api.syncAppStoreTransaction(signedTransactionInfo: result.jwsRepresentation)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result,
                  productIdsForSync.contains(transaction.productID),
                  api.hasToken else {
                continue
            }

            do {
                plan = try await api.syncAppStoreTransaction(signedTransactionInfo: result.jwsRepresentation)
                await transaction.finish()
            } catch {
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
