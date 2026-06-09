import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppSettings.onboardingDoneKey) private var onboardingDone = false

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            CanvassMapView()
                .tabItem { Label("Canvass", systemImage: "map.fill") }
                .tag(AppState.Tab.map)

            AssistantView()
                .tabItem { Label("Archie AI", systemImage: "sparkles") }
                .tag(AppState.Tab.assistant)

            LeadsView()
                .tabItem { Label("Leads", systemImage: "person.3.fill") }
                .tag(AppState.Tab.leads)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppState.Tab.settings)
        }
        .fullScreenCover(isPresented: .init(
            get: { !onboardingDone },
            set: { newValue in onboardingDone = !newValue }
        )) {
            OnboardingView(done: $onboardingDone)
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
        .environmentObject(LeadStore())
        .environmentObject(LocationManager())
}
