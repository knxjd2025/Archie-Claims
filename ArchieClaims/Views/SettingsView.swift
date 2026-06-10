import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var syncService: LeadSyncService
    @AppStorage(AppSettings.searchRadiusKey) private var radiusMiles = AppSettings.defaultRadiusMiles
    @AppStorage(AppSettings.lookbackDaysKey) private var lookbackDays = AppSettings.defaultLookbackDays
    @AppStorage(AppSettings.modelOverrideKey) private var modelOverride = ""
    @AppStorage(AppSettings.proxyBaseURLKey) private var proxyBaseURL = ""
    @AppStorage(AppSettings.assistantModeKey) private var assistantModeRaw = ""
    @AppStorage(AppSettings.archieBaseURLKey) private var archieBaseURL = ""

    @State private var signedInEmail: String?
    @State private var apiKeyDraft = ""
    @State private var hasStoredKey = false
    @State private var showSavedConfirmation = false
    @State private var showAdvanced = false

    private var assistantMode: AppSettings.AssistantMode {
        AppSettings.assistantMode(from: assistantModeRaw)
    }

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
                signedInEmail = ArchieBackendService.signedInEmail
            }
            .alert("API key saved to Keychain", isPresented: $showSavedConfirmation) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    // MARK: - AI

    private var aiSection: some View {
        Section {
            if assistantMode == .archie {
                archieAccountRows
            } else {
                anthropicKeyRows
            }

            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                Picker("AI backend", selection: $assistantModeRaw) {
                    Text("Archie account").tag("")
                    Text("Anthropic API key").tag(AppSettings.AssistantMode.anthropic.rawValue)
                }
                if assistantMode == .archie {
                    TextField("Backend URL (default: \(ArchieBackendService.defaultBaseURL.absoluteString))", text: $archieBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } else {
                    TextField("Model (default: \(ClaudeService.defaultModel))", text: $modelOverride)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Proxy base URL (optional, https://…)", text: $proxyBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
        } header: {
            Text("AI Assistant")
        } footer: {
            if assistantMode == .archie {
                Text("One Archie account for everything — this app and app.archie.now share the same accounts, backend, and company profile. New accounts are free. Your password is stored in the device Keychain only to refresh your session.")
            } else {
                Text("Archie runs on Claude Opus 4.8 using your own Anthropic API key. The key never leaves this device except to call the API directly. Usage is billed to your Anthropic account.")
            }
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

    @ViewBuilder
    private var anthropicKeyRows: some View {
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
            LabeledContent("AI Backend", value: assistantMode == .archie
                           ? "Archie CRM (managed)"
                           : AppSettings.model(from: modelOverride))
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
