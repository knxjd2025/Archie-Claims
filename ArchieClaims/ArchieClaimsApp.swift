import SwiftUI

@main
struct ArchieClaimsApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var leadStore = LeadStore()
    @StateObject private var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(leadStore)
                .environmentObject(locationManager)
        }
    }
}

/// Cross-tab app state: tab selection plus the property context handoff from
/// the map's property sheet into the AI assistant.
@MainActor
final class AppState: ObservableObject {
    enum Tab: Hashable {
        case map
        case assistant
        case leads
        case settings
    }

    @Published var selectedTab: Tab = .map
    /// Storm/property context queued for the assistant ("Ask Archie" flow).
    @Published var pendingPropertyContext: String?

    func askArchie(about context: String) {
        pendingPropertyContext = context
        selectedTab = .assistant
    }
}
