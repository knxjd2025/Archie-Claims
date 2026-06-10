import SwiftUI

/// Data-credits store. Shows the balance, subscription, and credit packages.
/// Purchasing is not wired yet (pending the Stripe/Apple-IAP decision), so this
/// is informational + a link to manage the plan on the web for now.
struct CreditStoreView: View {
    @Environment(\.dismiss) private var dismiss
    let info: ArchieBackendService.CreditInfo?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "creditcard.circle.fill")
                            .font(.title)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading) {
                            Text("\(info?.balance ?? 0) data credits")
                                .font(.title3.bold())
                            Text("1 credit pulls one verified owner report.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let info, let monthly = info.subscriptionMonthly {
                    Section("Subscription") {
                        planRow(
                            title: "Archie Pro — Monthly",
                            detail: "\(info.monthlyCredits ?? 100) credits / month",
                            price: usd(monthly) + "/mo"
                        )
                        if let annual = info.subscriptionAnnual {
                            planRow(
                                title: "Archie Pro — Annual",
                                detail: "\(info.monthlyCredits ?? 100) credits / month · best value",
                                price: usd(annual) + "/yr"
                            )
                        }
                    }
                }

                if let packages = info?.packages, !packages.isEmpty {
                    Section("Credit packs") {
                        ForEach(packages) { pack in
                            planRow(
                                title: "\(pack.credits) credits",
                                detail: String(format: "%.0f¢ per credit", (pack.usd / Double(pack.credits)) * 100),
                                price: usd(pack.usd)
                            )
                        }
                    }
                }

                if let payg = info?.paygPerCredit {
                    Section {
                        planRow(title: "Pay as you go", detail: "Single credits, no commitment", price: usd(payg) + "/credit")
                    }
                }

                Section {
                    Link(destination: URL(string: "https://app.archie.now/billing")!) {
                        Label("Manage plan & buy credits", systemImage: "arrow.up.right.square")
                    }
                } footer: {
                    Text("In-app purchasing is coming soon. For now, manage your plan and credits at app.archie.now.")
                }
            }
            .navigationTitle("Data Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func planRow(title: String, detail: String, price: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(price).font(.subheadline.weight(.semibold))
        }
    }

    private func usd(_ value: Double) -> String {
        value == value.rounded() ? String(format: "$%.0f", value) : String(format: "$%.2f", value)
    }
}
