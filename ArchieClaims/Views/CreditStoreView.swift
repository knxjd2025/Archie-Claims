import SwiftUI
import StoreKit

/// Data-credits store with two ways to pay per item: Apple In-App Purchase at
/// the normal price, or Stripe on the web at a discount. Stripe checkout opens
/// in Safari (the purchase happens outside the app); Apple purchases redeem
/// with the backend, which grants the credits.
struct CreditStoreView: View {
    @Environment(\.dismiss) private var dismiss

    let info: ArchieBackendService.CreditInfo?
    /// Called after a successful Apple purchase so the caller can refresh balance.
    var onPurchased: ((Int) -> Void)?

    @EnvironmentObject private var store: StoreManager
    @State private var balance: Int = 0
    @State private var message: String?
    @State private var restoring = false

    private var subscriptions: [ArchieBackendService.CreditItem] {
        info?.items.filter { $0.kind == "subscription" } ?? []
    }
    private var packs: [ArchieBackendService.CreditItem] {
        info?.items.filter { $0.kind == "pack" } ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "creditcard.circle.fill")
                            .font(.title).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading) {
                            Text("\(balance) data credits").font(.title3.bold())
                            Text("1 credit pulls one verified owner report.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Credits are added instantly to your account.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if !subscriptions.isEmpty {
                    Section("Subscription — \(subscriptions.first?.credits ?? 100) credits / month") {
                        ForEach(subscriptions) { itemRows($0) }
                    }
                }
                if !packs.isEmpty {
                    Section("Credit packs") {
                        ForEach(packs) { itemRows($0) }
                    }
                }

                if let message {
                    Section { Text(message).font(.caption).foregroundStyle(.secondary) }
                }

                Section {
                    Button {
                        restorePurchases()
                    } label: {
                        HStack {
                            Text("Restore Purchases")
                            if restoring {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(restoring)
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("""
                        Subscriptions renew automatically unless cancelled at least 24 hours before \
                        the end of the current period. Manage or cancel anytime in Settings → \
                        Apple Account → Subscriptions. Payment is charged to your Apple Account.
                        """)
                        HStack(spacing: 6) {
                            Link("Privacy Policy", destination: URL(string: "https://app.archie.now/privacy.html")!)
                            Text("·")
                            Link("Terms of Use", destination: URL(string: "https://app.archie.now/terms.html")!)
                        }
                    }
                    .font(.caption2)
                }
            }
            .navigationTitle("Data Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                balance = info?.balance ?? 0
                store.onBalanceUpdate = { newBalance in
                    balance = newBalance
                    onPurchased?(newBalance)
                }
                await store.loadProducts(ids: (info?.items ?? []).map(\.appleProductID))
            }
        }
    }

    @ViewBuilder
    private func itemRows(_ item: ArchieBackendService.CreditItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.label).font(.subheadline.weight(.semibold))

            // Apple In-App Purchase (only if the StoreKit product loaded).
            if let product = store.product(for: item.appleProductID) {
                Button {
                    buyWithApple(item, product: product)
                } label: {
                    payLabel(system: "apple.logo", title: "Buy", price: product.displayPrice)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.purchasingID != nil)
            }
            if store.purchasingID == item.appleProductID {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private func payLabel(system: String, title: String, price: String) -> some View {
        VStack(spacing: 1) {
            Label(title, systemImage: system).font(.caption.weight(.medium))
            Text(price).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Purchase flows

    private func buyWithApple(_ item: ArchieBackendService.CreditItem, product: Product) {
        message = nil
        Task {
            do {
                // StoreManager redeems with the backend BEFORE finishing the
                // transaction, and updates `balance` via onBalanceUpdate.
                let outcome = try await store.purchase(product)
                switch outcome {
                case .success(let newBalance):
                    message = "Credits added. You now have \(newBalance)."
                case .pending:
                    message = "Your purchase is pending approval. Credits will appear once it's approved."
                case .cancelled:
                    break
                }
            } catch {
                message = error.localizedDescription
            }
        }
    }

    /// Re-syncs the App Store transaction history (App Review requires a visible
    /// restore mechanism), then redeems anything unfinished with the backend.
    private func restorePurchases() {
        message = nil
        restoring = true
        Task {
            do {
                try await AppStore.sync()
                await store.redeemPending()
                message = "Purchases restored. Any credits that hadn't arrived have been re-applied."
            } catch {
                message = error.localizedDescription
            }
            restoring = false
        }
    }

}
