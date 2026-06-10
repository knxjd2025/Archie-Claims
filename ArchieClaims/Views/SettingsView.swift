import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var syncService: LeadSyncService
    @AppStorage(AppSettings.searchRadiusKey) private var radiusMiles = AppSettings.defaultRadiusMiles
    @AppStorage(AppSettings.lookbackDaysKey) private var lookbackDays = AppSettings.defaultLookbackDays

    @State private var signedInEmail: String?

    var body: some View {
        NavigationStack {
            Form {
                aiSection
                stormSection
                aboutSection
            }
            .navigationTitle("Settings")
            .onAppear {
                signedInEmail = ArchieBackendService.signedInEmail
            }
        }
    }

    // MARK: - AI

    private var aiSection: some View {
        Section {
            archieAccountRows
        } header: {
            Text("Account")
        } footer: {
            Text("Sign in with your Archie account to turn on the AI assistant, owner lookups, and CRM sync. New accounts are free. Your password is stored only in this device's Keychain to keep you signed in.")
        }
    }

    @ViewBuilder
    private var archieAccountRows: some View {
        if let signedInEmail {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Signed in to Archie")
                        .font(.subheadline)
                    Text(signedInEmail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Sign Out", role: .destructive) {
                ArchieBackendService.signOut()
                self.signedInEmail = nil
            }
        } else {
            ArchieAccountForm { email in
                signedInEmail = email
                // Drain any leads queued while signed out.
                syncService.requestSync()
            }
        }
    }

    // MARK: - Storm data

    private var stormSection: some View {
        Section {
            VStack(alignment: .leading) {
                Text("Search radius: \(Int(radiusMiles)) mi")
                    .font(.subheadline)
                Slider(value: $radiusMiles, in: 1...25, step: 1)
            }
            Picker("Lookback", selection: $lookbackDays) {
                ForEach(lookbackOptions, id: \.self) { days in
                    Text(AppSettings.lookbackLabel(days: days)).tag(days)
                }
            }
        } header: {
            Text("Storm Data")
        } footer: {
            Text("How far around a tapped house and how far back (up to 2 years) to search NOAA SPC storm reports. Long lookbacks download one small daily file per day on first use, then stay cached on-device.")
        }
    }

    /// Preset windows, keeping any custom value carried over from older builds.
    private var lookbackOptions: [Int] {
        var options = AppSettings.lookbackPresets
        if !options.contains(lookbackDays) {
            options.append(lookbackDays)
            options.sort()
        }
        return options
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: appVersion)
            LabeledContent("AI Backend", value: "Archie CRM (managed)")
            Link(destination: URL(string: "https://www.spc.noaa.gov/climo/reports/")!) {
                Label("NOAA SPC Storm Reports", systemImage: "cloud.bolt.rain")
            }
            Link(destination: URL(string: "https://www.weather.gov/documentation/services-web-api")!) {
                Label("NWS API", systemImage: "antenna.radiowaves.left.and.right")
            }
        } header: {
            Text("About")
        } footer: {
            Text("""
            Storm data: NOAA Storm Prediction Center & National Weather Service (public domain, preliminary, \
            unverified). Contact lookups open free public websites; verify everything before use. AI responses \
            are guidance only — not legal, insurance, or financial advice. Follow local solicitation laws, \
            do-not-knock lists, and TCPA rules when contacting homeowners.
            """)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
