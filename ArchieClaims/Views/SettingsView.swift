import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.searchRadiusKey) private var radiusMiles = AppSettings.defaultRadiusMiles
    @AppStorage(AppSettings.lookbackDaysKey) private var lookbackDays = AppSettings.defaultLookbackDays
    @AppStorage(AppSettings.modelOverrideKey) private var modelOverride = ""
    @AppStorage(AppSettings.proxyBaseURLKey) private var proxyBaseURL = ""

    @State private var apiKeyDraft = ""
    @State private var hasStoredKey = false
    @State private var showSavedConfirmation = false
    @State private var showAdvanced = false

    var body: some View {
        NavigationStack {
            Form {
                aiSection
                stormSection
                aboutSection
            }
            .navigationTitle("Settings")
            .onAppear {
                hasStoredKey = (KeychainStore.read()?.isEmpty == false)
            }
            .alert("API key saved to Keychain", isPresented: $showSavedConfirmation) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    // MARK: - AI

    private var aiSection: some View {
        Section {
            HStack {
                Image(systemName: hasStoredKey ? "checkmark.seal.fill" : "key.fill")
                    .foregroundStyle(hasStoredKey ? .green : .secondary)
                Text(hasStoredKey ? "API key on file (stored in Keychain)" : "No API key yet")
                    .font(.subheadline)
            }

            SecureField("Paste Anthropic API key (sk-ant-…)", text: $apiKeyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("Save Key") {
                let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                KeychainStore.save(trimmed)
                apiKeyDraft = ""
                hasStoredKey = true
                showSavedConfirmation = true
            }
            .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if hasStoredKey {
                Button("Remove Key", role: .destructive) {
                    KeychainStore.delete()
                    hasStoredKey = false
                }
            }

            Link(destination: URL(string: "https://console.anthropic.com/")!) {
                Label("Get an API key (console.anthropic.com)", systemImage: "arrow.up.right.square")
            }

            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                TextField("Model (default: \(ClaudeService.defaultModel))", text: $modelOverride)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Proxy base URL (optional, https://…)", text: $proxyBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
        } header: {
            Text("AI Assistant")
        } footer: {
            Text("Archie runs on Claude Opus 4.8 using your own Anthropic API key. The key never leaves this device except to call the API directly. Usage is billed to your Anthropic account.")
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
            Stepper("Lookback: \(lookbackDays) days", value: $lookbackDays, in: 7...90, step: 1)
        } header: {
            Text("Storm Data")
        } footer: {
            Text("How far around a tapped house and how many days back to search NOAA SPC storm reports. Longer lookbacks download more daily files on first use.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: appVersion)
            LabeledContent("AI Model", value: AppSettings.model(from: modelOverride))
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
