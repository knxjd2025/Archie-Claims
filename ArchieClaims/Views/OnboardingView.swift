import SwiftUI

/// First-run walkthrough: what the app does, where the data comes from, and
/// (optionally) setting up the AI key.
struct OnboardingView: View {
    @Binding var done: Bool
    @State private var page = 0

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
                    symbol: "cloud.bolt.rain.fill",
                    title: "Real Storm Evidence",
                    text: "Data comes straight from NOAA's Storm Prediction Center and the National Weather Service — free, official, and updated daily. Reports are preliminary; always verify on the roof."
                )
                .tag(1)

                OnboardPage(
                    symbol: "sparkles",
                    title: "Archie, Your AI Sidekick",
                    text: "Door scripts, damage photo checklists, claim explanations, follow-up texts — powered by Archie. Sign in or create a free account (same login as app.archie.now) to turn it on."
                )
                .tag(2)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 10) {
                Button {
                    if page < 2 {
                        withAnimation { page += 1 }
                    } else {
                        done = true
                    }
                } label: {
                    Text(page < 2 ? "Next" : "Start Canvassing")
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
