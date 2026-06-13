import SwiftUI
import RevenueCat
import RevenueCatUI

/// RevenueCat paywall for Archie Canvass Pro, driven by the paywall designed
/// in the RevenueCat dashboard (Offerings → current offering → Paywall).
struct ProPaywallView: View {
    @EnvironmentObject private var revenueCat: RevenueCatManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PaywallView(displayCloseButton: true)
            .onPurchaseCompleted { customerInfo in
                if customerInfo.entitlements[RevenueCatManager.proEntitlementID]?.isActive == true {
                    dismiss()
                }
            }
            .onRestoreCompleted { customerInfo in
                if customerInfo.entitlements[RevenueCatManager.proEntitlementID]?.isActive == true {
                    dismiss()
                }
            }
    }
}

/// RevenueCat Customer Center: self-serve subscription management, refund
/// requests, and cancellation flows, configured in the dashboard.
struct CustomerCenterSheet: View {
    var body: some View {
        CustomerCenterView()
    }
}

/// Gate any view behind the Pro entitlement: shows the paywall automatically
/// when the user isn't subscribed. Apply where Pro features live, e.g.
/// `.proGate()` on a Pro-only screen.
extension View {
    func proGate() -> some View {
        presentPaywallIfNeeded(
            requiredEntitlementIdentifier: RevenueCatManager.proEntitlementID
        )
    }
}
