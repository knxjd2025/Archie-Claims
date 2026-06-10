import Foundation
import StoreKit

/// StoreKit 2 wrapper for buying Archie data credits via Apple In-App Purchase.
/// Products (consumable packs + auto-renewable subscriptions) must be created in
/// App Store Connect with the product IDs returned by the backend catalog
/// (`apple_product_id`). After a successful purchase the verified transaction is
/// redeemed with the backend, which grants the credits.
@MainActor
final class StoreManager: ObservableObject {
    @Published private(set) var products: [String: Product] = [:]
    @Published var purchasingID: String?
    @Published var lastError: String?

    enum PurchaseOutcome {
        case success(transactionID: String, productID: String)
        case cancelled
        case pending
    }

    enum StoreError: LocalizedError {
        case unverified
        case productUnavailable

        var errorDescription: String? {
            switch self {
            case .unverified: return "Apple couldn't verify that purchase. No credits were charged."
            case .productUnavailable: return "That purchase option isn't available right now."
            }
        }
    }

    /// Loads StoreKit products for the given App Store Connect product IDs.
    func loadProducts(ids: [String]) async {
        guard !ids.isEmpty else { return }
        do {
            let loaded = try await Product.products(for: ids)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        } catch {
            lastError = error.localizedDescription
        }
    }

    func product(for id: String) -> Product? { products[id] }

    /// Buys a product and returns the verified transaction id (to redeem on the
    /// backend). Throws on verification failure; returns .cancelled/.pending for
    /// the non-success StoreKit results.
    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        purchasingID = product.id
        defer { purchasingID = nil }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                let id = String(transaction.id)
                await transaction.finish()
                return .success(transactionID: id, productID: product.id)
            case .unverified:
                throw StoreError.unverified
            }
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }
}
