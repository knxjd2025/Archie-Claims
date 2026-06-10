import SwiftUI

@main
struct ArchieClaimsApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var leadStore: LeadStore
    @StateObject private var locationManager = LocationManager()
    @StateObject private var syncService: LeadSyncService
    @StateObject private var storeManager = StoreManager()

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppSettings.archieBaseURLKey) private var archieBaseURL = ""

    init() {
        let store = LeadStore()
        _leadStore = StateObject(wrappedValue: store)
        _syncService = StateObject(wrappedValue: LeadSyncService(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(leadStore)
                .environmentObject(locationManager)
                .environmentObject(syncService)
                .environmentObject(storeManager)
                .task {
                    syncService.updateBaseURL(archieBaseURL)
                    syncService.start()
                    // Redeem any purchase/renewal left unfinished (e.g. the app
                    // was killed mid-redeem, or a subscription renewed while closed).
                    storeManager.configure(baseURLOverride: archieBaseURL)
                    storeManager.startListening()
                }
                .onChange(of: archieBaseURL) {
                    syncService.updateBaseURL(archieBaseURL)
                    storeManager.configure(baseURLOverride: archieBaseURL)
                }
                .onChange(of: scenePhase) {
                    if scenePhase == .active {
                        syncService.requestSync()
                        Task { await storeManager.redeemPending() }
                    }
                }
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
