import SwiftUI

/// First-run walkthrough: what the app does, where the data comes from, how to
/// log doors fast, and a primed location-permission ask on the final page.
struct OnboardingView: View {
    @Binding var done: Bool
    @EnvironmentObject private var locationManager: LocationManager
    @State private var page = 0

    private let lastPage = 3

    var body: some View {
        VStack {
            TabView(selection: $page) {
                OnboardPage(
                    symbol: "map.fill",
                    title: "Canvass Smarter",
                    text: "Tap any house on the map to instantly pull NOAA storm reports near it — hail size, wind speed, tornado tracks — plus free public links to owner and contact info."
                )
                .tag(0)

                OnboardPage(
                    symbol: "bolt.fill",
                    title: "Log Doors in One Tap",
                    text: "Turn on ⚡️ Quick Log, then every roof you tap logs the knock — Not Home, Interested, Appointment, Signed — in a single tap. The address and storm evidence fill in automatically while you walk to the next door."
                )
                .tag(1)

                OnboardPage(
                    symbol: "sparkles",
                    title: "Archie, Your AI Sidekick",
                    text: "Door scripts, damage photo checklists, claim explanations, follow-up texts — powered by Archie. Sign in or create a free account (same login as app.archie.now) to turn it on."
                )
                .tag(2)

                OnboardPage(
                    symbol: "location.fill.viewfinder",
                    title: "Find Your Turf",
                    text: "Archie centers the map on the neighborhood you're standing in so you start canvassing immediately. Your location stays on this phone — it's never uploaded or shared."
                )
                .tag(3)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 10) {
                Button {
                    if page < lastPage {
                        withAnimation { page += 1 }
                    } else {
                        // Prime, then fire the system location prompt on tap.
                        locationManager.requestPermission()
                        done = true
                    }
                } label: {
                    Text(buttonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)

                Text("Respect no-soliciting signs, local permit rules, and do-not-knock lists.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private var buttonTitle: String {
        switch page {
        case lastPage: return "Find My Turf"
        case lastPage - 1: return "Next"
        default: return "Next"
        }
    }
}

private struct OnboardPage: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.title.bold())
            Text(text)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
            Spacer()
        }
    }
}
