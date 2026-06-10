import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var leadStore: LeadStore
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
        .safeAreaInset(edge: .top) {
            if let error = leadStore.lastSaveError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        leadStore.lastSaveError = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                .padding(10)
                .background(.red.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
            }
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
