import Foundation
import RevenueCat

/// RevenueCat wrapper for the "Archie Canvass Pro" subscription.
///
/// Division of labor with `StoreManager`: RevenueCat owns the Pro
/// subscription (paywall, entitlement state, restore, Customer Center);
/// `StoreManager` keeps owning the consumable credit packs, whose
/// grant-then-finish money path must stay backend-driven. Don't purchase
/// the credit packs through RevenueCat.
@MainActor
final class RevenueCatManager: ObservableObject {

    /// The entitlement configured in the RevenueCat dashboard.
    static let proEntitlementID = "Archie Canvass Pro"

    /// Test Store key. Before shipping, replace with the production
    /// App Store key (appl_…) from RevenueCat → Project → API Keys.
    private static let apiKey = "test_QaXZhipvsIQaQCWbibwGGyYQqrr"

    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var offerings: Offerings?
    @Published var isPurchasing = false
    @Published var lastError: String?

    /// True when the "Archie Canvass Pro" entitlement is active.
    var isPro: Bool {
        customerInfo?.entitlements[Self.proEntitlementID]?.isActive == true
    }

    private var infoStreamTask: Task<Void, Never>?

    // MARK: - Configuration

    /// Call once from the App initializer, before any view needs purchases.
    static func configureSDK() {
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(
            with: Configuration.Builder(withAPIKey: apiKey)
                .with(storeKitVersion: .storeKit2)
                .build()
        )
    }

    /// Begin observing entitlement changes and load offerings.
    func start() {
        guard infoStreamTask == nil else { return }
        infoStreamTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.customerInfo = info
            }
        }
        Task { await loadOfferings() }
    }

    func loadOfferings() async {
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            lastError = Self.message(for: error)
        }
    }

    // MARK: - Purchases

    /// Purchases a paywall package. Returns true when Pro is now active.
    @discardableResult
    func purchase(_ package: Package) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            customerInfo = result.customerInfo
            return !result.userCancelled && isPro
        } catch ErrorCode.purchaseCancelledError {
            return false
        } catch {
            lastError = Self.message(for: error)
            return false
        }
    }

    /// Restores prior purchases (required by App Review on any paywall).
    @discardableResult
    func restorePurchases() async -> Bool {
        do {
            customerInfo = try await Purchases.shared.restorePurchases()
            return isPro
        } catch {
            lastError = Self.message(for: error)
            return false
        }
    }

    // MARK: - Identity

    /// Ties RevenueCat's customer record to the signed-in Archie account so
    /// Pro follows the account across devices.
    func logIn(appUserID: String) {
        Task {
            do {
                let (info, _) = try await Purchases.shared.logIn(appUserID)
                customerInfo = info
            } catch {
                lastError = Self.message(for: error)
            }
        }
    }

    func logOut() {
        Task {
            // logOut throws if already anonymous — safe to ignore.
            customerInfo = try? await Purchases.shared.logOut()
        }
    }

    // MARK: - Errors

    private static func message(for error: Error) -> String {
        switch error {
        case ErrorCode.networkError:
            return "Network problem reaching the App Store. Check your connection and try again."
        case ErrorCode.offlineConnectionError:
            return "You appear to be offline. Try again when you're connected."
        case ErrorCode.paymentPendingError:
            return "Your purchase is awaiting approval (Ask to Buy). Pro unlocks once it's approved."
        case ErrorCode.productAlreadyPurchasedError:
            return "You already own this. Try Restore Purchases."
        case ErrorCode.configurationError, ErrorCode.unexpectedBackendResponseError:
            return "The store isn't available right now. Please try again later."
        default:
            return error.localizedDescription
        }
    }
}
