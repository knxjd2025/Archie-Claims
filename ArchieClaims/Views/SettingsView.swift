import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var syncService: LeadSyncService
    @EnvironmentObject private var revenueCat: RevenueCatManager
    @AppStorage(AppSettings.searchRadiusKey) private var radiusMiles = AppSettings.defaultRadiusMiles
    @AppStorage(AppSettings.lookbackDaysKey) private var lookbackDays = AppSettings.defaultLookbackDays

    @AppStorage(AppSettings.archieBaseURLKey) private var archieBaseURL = ""

    @State private var signedInEmail: String?
    @State private var showDeleteConfirm = false
    @State private var deleting = false
    @State private var deleteError: String?
    @State private var showPaywall = false
    @State private var showCustomerCenter = false
    @State private var restoring = false

    var body: some View {
        NavigationStack {
            Form {
                aiSection
                proSection
                stormSection
                aboutSection
            }
            .navigationTitle("Settings")
            .onAppear {
                signedInEmail = ArchieBackendService.signedInEmail
            }
            .confirmationDialog(
                "Delete your account?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) { deleteAccount() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your Archie account and personal information. Purchased credits are forfeited. This can't be undone.")
            }
            .alert(
                "Couldn't Delete Account",
                isPresented: Binding(
                    get: { deleteError != nil },
                    set: { if !$0 { deleteError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    // MARK: - Pro subscription (RevenueCat)

    private var proSection: some View {
        Section {
            if revenueCat.isPro {
                HStack {
                    Image(systemName: "star.circle.fill")
                        .foregroundStyle(.yellow)
                    Text("Archie Canvass Pro is active")
                        .font(.subheadline)
                }
                Button("Manage Subscription") {
                    showCustomerCenter = true
                }
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack {
                        Image(systemName: "star.circle")
                        Text("Upgrade to Archie Canvass Pro")
                    }
                }
                Button {
                    restoring = true
                    Task {
                        await revenueCat.restorePurchases()
                        restoring = false
                    }
                } label: {
                    HStack {
                        Text("Restore Purchases")
                        if restoring {
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(restoring)
            }
            if let storeError = revenueCat.lastError {
                Label(storeError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Archie Canvass Pro")
        }
        .sheet(isPresented: $showPaywall) {
            ProPaywallView()
        }
        .sheet(isPresented: $showCustomerCenter) {
            CustomerCenterSheet()
        }
    }

    // MARK: - AI

    private var aiSection: some View {
        Section {
            archieAccountRows
        } header: {
            Text("Account")
        } footer: {
            Text("Sign in with your existing Archie account (app.archie.now) to turn on the AI assistant, owner lookups, and CRM sync. Your password is stored only in this device's Keychain to keep you signed in.")
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
                revenueCat.logOut()
                self.signedInEmail = nil
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Text("Delete Account")
                    if deleting {
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(deleting)
        } else {
            ArchieAccountForm { email in
                signedInEmail = email
                revenueCat.logIn(appUserID: email)
                // Drain any leads queued while signed out.
                syncService.requestSync()
            }
        }
    }

    /// Calls the backend to permanently delete the account, then clears the
    /// local session (the service signs out on success).
    private func deleteAccount() {
        deleting = true
        Task {
            do {
                let service = ArchieBackendService(
                    baseURL: AppSettings.archieBaseURL(from: archieBaseURL)
                )
                try await service.deleteAccount()
                signedInEmail = nil
            } catch {
                deleteError = error.localizedDescription
            }
            deleting = false
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
