import Foundation
import StoreKit

/// StoreKit 2 wrapper for buying Archie data credits via Apple In-App Purchase.
///
/// Money-path rule: a StoreKit transaction is only `finish()`ed AFTER the
/// backend confirms the credit grant. If the grant call fails (or the app is
/// killed mid-redeem), the transaction stays in StoreKit's unfinished queue and
/// is retried by the launch listener (`startListening`) — so a charged purchase
/// is never lost. The backend redeem is idempotent on the transaction id, so
/// retries never double-grant.
@MainActor
final class StoreManager: ObservableObject {
    @Published private(set) var products: [String: Product] = [:]
    @Published var purchasingID: String?
    @Published var lastError: String?

    /// Called whenever a redeem succeeds (purchase, renewal, or recovery) with
    /// the new balance, so the UI can refresh.
    var onBalanceUpdate: ((Int) -> Void)?

    private var baseURLOverride = ""
    private var updatesTask: Task<Void, Never>?

    enum PurchaseOutcome {
        case success(balance: Int)
        case cancelled
        case pending
    }

    enum StoreError: LocalizedError {
        case unverified
        var errorDescription: String? {
            "Apple couldn't verify that purchase. No credits were charged."
        }
    }

    private var service: ArchieBackendService {
        ArchieBackendService(baseURL: AppSettings.archieBaseURL(from: baseURLOverride))
    }

    func configure(baseURLOverride: String) {
        self.baseURLOverride = baseURLOverride
    }

    /// Starts the transaction listener and redeems anything left unfinished from
    /// a prior session (interrupted redeem, or a subscription renewal that
    /// arrived while the app was closed). Call once at launch.
    func startListening() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.redeemAndFinish(result)
            }
        }
        Task { await redeemPending() }
    }

    /// Redeems every unfinished verified transaction with the backend.
    func redeemPending() async {
        for await result in Transaction.unfinished {
            await redeemAndFinish(result)
        }
    }

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

    /// Buys a product, then redeems it with the backend BEFORE finishing.
    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        purchasingID = product.id
        defer { purchasingID = nil }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw StoreError.unverified
            }
            // Grant FIRST; only finish once the backend acknowledges.
            let balance = try await service.redeemIAP(
                productID: transaction.productID,
                transactionID: String(transaction.id),
                jws: verification.jwsRepresentation
            )
            await transaction.finish()
            onBalanceUpdate?(balance)
            return .success(balance: balance)
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    /// Redeems a (possibly recovered) transaction and finishes it only on success.
    /// Leaves it unfinished on failure so it's retried next launch/update.
    private func redeemAndFinish(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        // Can't redeem without an account; retry after the user signs in.
        guard ArchieBackendService.signedInEmail != nil else { return }
        do {
            let balance = try await service.redeemIAP(
                productID: transaction.productID,
                transactionID: String(transaction.id),
                jws: result.jwsRepresentation
            )
            await transaction.finish()
            onBalanceUpdate?(balance)
        } catch {
            // Leave unfinished; the launch listener will try again.
        }
    }
}
