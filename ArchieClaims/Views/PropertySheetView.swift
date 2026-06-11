import SwiftUI
import CoreLocation
import UIKit

/// Shown when the canvasser taps a house: address, storm evidence, public
/// contact lookups, save-as-lead, and a handoff into the AI assistant.
struct PropertySheetView: View {
    let coordinate: CLLocationCoordinate2D

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var leadStore: LeadStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettings.searchRadiusKey) private var radiusMiles = AppSettings.defaultRadiusMiles
    @AppStorage(AppSettings.lookbackDaysKey) private var lookbackDays = AppSettings.defaultLookbackDays
    @AppStorage(AppSettings.archieBaseURLKey) private var archieBaseURL = ""

    // Paid owner report (1 data credit, Tracerfy).
    @State private var ownerReport: ArchieBackendService.OwnerReport?
    @State private var loadingOwner = false
    @State private var ownerMessage: String?
    @State private var confirmOwnerPurchase = false
    @State private var creditInfo: ArchieBackendService.CreditInfo?
    @State private var showCreditStore = false

    @State private var geocode: GeocodingService.Result?
    @State private var geocodeFailed = false
    @State private var stormLoadState: LoadState = .loading
    @State private var nearbyReports: [NearbyStormReport] = []
    @State private var alerts: [NWSAlert] = []
    @State private var safariURL: IdentifiableURL?

    // Manual contact entry (pre-filled from an existing lead).
    @State private var homeownerName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var contactNotes = ""
    @State private var prefilled = false

    // Free property characteristics (auto-filled from OpenStreetMap).
    @State private var property: PropertyDataService.PropertyInfo?
    @State private var loadingProperty = true

    enum LoadState {
        case loading
        case loaded
    }

    struct IdentifiableURL: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var addressLine: String {
        geocode?.address ?? String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    var body: some View {
        NavigationStack {
            List {
                addressSection
                logDoorSection
                homeownerSection
                stormSection
                ownerLookupSection
                actionSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: prefillFromExistingLead)
            .task {
                async let geo: Void = loadGeocode()
                async let storms: Void = loadStorms()
                async let prop: Void = loadProperty()
                async let credits: Void = loadCredits()
                _ = await (geo, storms, prop, credits)
            }
            .sheet(item: $safariURL) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showCreditStore, onDismiss: { Task { await loadCredits() } }) {
                CreditStoreView(info: creditInfo) { newBalance in
                    creditInfo?.balance = newBalance
                }
            }
        }
    }

    // MARK: - Sections

    private var addressSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "house.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(addressLine)
                        .font(.headline)
                        .textSelection(.enabled)
                    if geocodeFailed {
                        Text("Couldn't resolve a street address — storm data still applies to this spot.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let existing = existingLead {
                        Label("Saved lead: \(existing.status.rawValue)", systemImage: existing.status.symbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(existing.status.color)
                    }
                }
            }

            if loadingProperty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking up property details…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let summary = property?.summary {
                Label(summary, systemImage: "building.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                openInMaps()
            } label: {
                Label("Open in Apple Maps", systemImage: "map")
            }
        }
    }

    private var homeownerSection: some View {
        Section {
            TextField("Homeowner name", text: $homeownerName)
                .textContentType(.name)
            TextField("Phone", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.emailAddress)
            TextField("Notes (damage seen, callbacks…)", text: $contactNotes, axis: .vertical)
                .lineLimit(2...5)
        } header: {
            Text("Homeowner")
        } footer: {
            Text("Type what you learn at the door. Saved with the lead and synced to your Archie CRM.")
        }
    }

    private func openInMaps() {
        let query = (geocode?.address ?? "\(coordinate.latitude),\(coordinate.longitude)")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=\(query)"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    private var stormSection: some View {
        Section {
            switch stormLoadState {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking NOAA storm reports…")
                        .foregroundStyle(.secondary)
                }
            case .loaded:
                if !alerts.isEmpty {
                    ForEach(alerts) { alert in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(alert.event, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red)
                            if let headline = alert.headline {
                                Text(headline)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if nearbyReports.isEmpty {
                    ContentUnavailableView(
                        "No reports in range",
                        systemImage: "cloud.sun",
                        description: Text("No SPC severe weather reports within \(Int(radiusMiles)) mi in the last \(AppSettings.lookbackLabel(days: lookbackDays)). Widen the radius or lookback in Settings.")
                    )
                } else {
                    ForEach(nearbyReports.prefix(12)) { item in
                        StormReportRow(item: item)
                    }
                    if nearbyReports.count > 12 {
                        NavigationLink {
                            StormHistoryView(reports: nearbyReports)
                        } label: {
                            Label("See all \(nearbyReports.count) storm reports", systemImage: "list.bullet")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
            }
        } header: {
            Text("Storm Evidence — \(Int(radiusMiles)) mi / \(AppSettings.lookbackLabel(days: lookbackDays))")
        } footer: {
            Text("Source: NOAA Storm Prediction Center reports & National Weather Service alerts. Preliminary, unverified data.")
        }
    }

    private var ownerLookupSection: some View {
        Section {
            ownerReportRows
            ForEach(publicLinks) { link in
                Button {
                    safariURL = IdentifiableURL(url: link.url)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.title)
                            .font(.subheadline.weight(.medium))
                        Text(link.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Owner & Contact Lookup")
        } footer: {
            Text(PublicRecordsLinks.complianceNote)
        }
    }

    @ViewBuilder
    private var ownerReportRows: some View {
        if let report = ownerReport {
            ownerResult(report)
        } else if loadingOwner {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Pulling owner report…").font(.subheadline)
            }
        } else if ArchieBackendService.signedInEmail != nil {
            Button {
                confirmOwnerPurchase = true
            } label: {
                HStack {
                    Label("Get Owner Report", systemImage: "person.text.rectangle")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("1 credit").font(.caption).foregroundStyle(.secondary)
                }
            }
            .confirmationDialog(
                creditInfo.map { "Pull verified owner info (name, phones, emails, mailing) for this property? Uses 1 of your \($0.balance) data credits." }
                    ?? "Pull verified owner info for this property? Uses 1 data credit.",
                isPresented: $confirmOwnerPurchase,
                titleVisibility: .visible
            ) {
                Button("Use 1 credit") { runOwnerReport() }
                Button("Cancel", role: .cancel) {}
            }
            if let info = creditInfo {
                Button {
                    showCreditStore = true
                } label: {
                    Text("\(info.balance) data credit\(info.balance == 1 ? "" : "s") left · Buy more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        } else {
            Label("Sign in to Archie to use owner lookup", systemImage: "person.crop.circle.badge.questionmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let ownerMessage {
            Text(ownerMessage)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func ownerResult(_ report: ArchieBackendService.OwnerReport) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("Owner report", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
                if let n = report.remainingCredits {
                    Text("\(n) credit\(n == 1 ? "" : "s") left").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let name = report.name { ownerLine("Owner", name) }
            ForEach(report.phones) { phone in
                HStack(spacing: 6) {
                    Text("Phone").font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                    Text(phone.number).font(.caption).textSelection(.enabled)
                    if let t = phone.type { Text(t).font(.caption2).foregroundStyle(.tertiary) }
                    if phone.dnc {
                        Text("DNC").font(.caption2.bold()).foregroundStyle(.red)
                            .padding(.horizontal, 4).background(Color.red.opacity(0.12), in: Capsule())
                    }
                }
            }
            ForEach(report.emails, id: \.self) { ownerLine("Email", $0) }
            if let mailing = report.mailingAddress { ownerLine("Mailing", mailing) }
            if let occ = report.ownerOccupied { ownerLine("Occupancy", occ ? "Owner-occupied" : "Absentee owner") }
            if let roof = report.roofMaterial { ownerLine("Roof", roof) }
            if let yr = report.yearBuilt { ownerLine("Built", String(yr)) }
            if let score = report.roofPropensityScore {
                ownerLine("Roof score", "\(score)\(report.roofPropensityCategory.map { " · \($0)" } ?? "")")
            }
            if report.litigator {
                Label("Known TCPA litigator — do not cold-call", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.red)
            }
            Button {
                fillContactFromOwner(report)
            } label: {
                Label("Use this info", systemImage: "arrow.down.doc")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .padding(.top, 2)
        }
    }

    private func ownerLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            Text(value).font(.caption).textSelection(.enabled)
        }
    }

    private var archieService: ArchieBackendService {
        ArchieBackendService(baseURL: AppSettings.archieBaseURL(from: archieBaseURL))
    }

    private func loadCredits() async {
        guard ArchieBackendService.signedInEmail != nil else { return }
        creditInfo = try? await archieService.creditInfo()
    }

    private func runOwnerReport() {
        loadingOwner = true
        ownerMessage = nil
        Task {
            do {
                ownerReport = try await archieService.ownerReport(
                    address: addressLine,
                    city: geocode?.city ?? "",
                    state: geocode?.state ?? "",
                    zip: geocode?.postalCode ?? ""
                )
            } catch ArchieBackendService.OwnerLookupError.insufficientCredits {
                creditInfo = try? await archieService.creditInfo()
                showCreditStore = true
            } catch {
                ownerMessage = error.localizedDescription
            }
            loadingOwner = false
        }
    }

    /// Pre-fills the editable contact fields from a paid report (rep can edit).
    private func fillContactFromOwner(_ report: ArchieBackendService.OwnerReport) {
        if let name = report.name, homeownerName.isEmpty { homeownerName = name }
        if let phone = report.phones.first?.number, self.phone.isEmpty { self.phone = phone }
        if let firstEmail = report.emails.first, self.email.isEmpty { self.email = firstEmail }
    }

    /// The five outcomes a canvasser logs at the door, in workflow order.
    private static let doorStatuses: [Lead.Status] = [.notHome, .interested, .appointment, .notInterested, .signed]

    private var logDoorSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Log this door")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.doorStatuses) { status in
                            Button {
                                logDoor(status)
                            } label: {
                                Label(status.rawValue, systemImage: status.symbolName)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        (existingLead?.status == status ? status.color : status.color.opacity(0.15)),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(existingLead?.status == status ? .white : status.color)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .sensoryFeedback(.success, trigger: existingLead?.status)
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                saveLead()
            } label: {
                Label(existingLead == nil ? "Save as Lead" : "Update Lead Snapshot", systemImage: "plus.circle.fill")
            }

            Button {
                appState.askArchie(about: propertyContext)
                dismiss()
            } label: {
                Label("Ask Archie (AI Claim Assistant)", systemImage: "sparkles")
            }

            ShareLink(item: shareText) {
                Label("Share Storm Report", systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: - Data

    private var existingLead: Lead? {
        leadStore.lead(near: coordinate.latitude, longitude: coordinate.longitude)
    }

    private var publicLinks: [PublicRecordsLinks.PublicLink] {
        PublicRecordsLinks.links(
            address: addressLine,
            city: geocode?.city ?? "",
            state: geocode?.state ?? "",
            postalCode: geocode?.postalCode ?? "",
            county: geocode?.county ?? ""
        )
    }

    private var stormSummary: String {
        StormDataService.summary(of: nearbyReports, lookbackDays: lookbackDays)
    }

    private var propertyContext: String {
        var lines = ["Address: \(addressLine)"]
        lines.append("Coordinates: \(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))")
        lines.append("Storm data (NOAA SPC, last \(AppSettings.lookbackLabel(days: lookbackDays)), \(Int(radiusMiles)) mi radius): \(stormSummary)")
        if !alerts.isEmpty {
            lines.append("Active NWS alerts: " + alerts.map(\.event).joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }

    private var shareText: String {
        "Storm report for \(addressLine)\n\(stormSummary)\n\nGenerated with Archie Canvass (data: NOAA SPC/NWS, preliminary)."
    }

    private func loadGeocode() async {
        geocode = await GeocodingService.reverseGeocode(coordinate)
        geocodeFailed = (geocode == nil)
    }

    private func loadStorms() async {
        stormLoadState = .loading
        async let reports = StormDataService.shared.reports(
            near: coordinate,
            radiusMiles: radiusMiles,
            lookbackDays: lookbackDays
        )
        async let active = StormDataService.shared.activeAlerts(at: coordinate)
        nearbyReports = await reports
        alerts = await active
        stormLoadState = .loaded
    }

    // MARK: - Loading & persistence

    private func loadProperty() async {
        loadingProperty = true
        property = await PropertyDataService.lookup(coordinate)
        // Carry auto-filled details onto an already-saved lead.
        if let info = property, var lead = existingLead {
            applyProperty(info, to: &lead)
            leadStore.update(lead)
        }
        loadingProperty = false
    }

    private func prefillFromExistingLead() {
        guard !prefilled else { return }
        prefilled = true
        if let lead = existingLead {
            homeownerName = lead.homeownerName
            phone = lead.phone
            email = lead.email
            contactNotes = lead.notes
        }
    }

    private func applyContact(to lead: inout Lead) {
        lead.homeownerName = homeownerName.trimmingCharacters(in: .whitespaces)
        lead.phone = phone.trimmingCharacters(in: .whitespaces)
        lead.email = email.trimmingCharacters(in: .whitespaces)
        lead.notes = contactNotes
    }

    private func applyProperty(_ info: PropertyDataService.PropertyInfo, to lead: inout Lead) {
        lead.propertyType = info.propertyType
        lead.stories = info.stories
        lead.roofShape = info.roofShape
    }

    private func newLead(status: Lead.Status, knockedNow: Bool) -> Lead {
        var lead = Lead(
            status: status,
            address: addressLine,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            stormSummary: stormSummary,
            lastKnockAt: knockedNow ? Date() : nil
        )
        applyContact(to: &lead)
        if let info = property { applyProperty(info, to: &lead) }
        return lead
    }

    private func saveLead() {
        if var lead = existingLead {
            lead.stormSummary = stormSummary
            applyContact(to: &lead)
            if let info = property { applyProperty(info, to: &lead) }
            leadStore.update(lead)
        } else {
            leadStore.add(newLead(status: .newLead, knockedNow: false))
        }
    }

    /// Logs a door outcome from the evidence view — creates or updates the lead
    /// (carrying any typed contact + auto-filled property data) and stamps the
    /// knock so it counts toward today's tally.
    private func logDoor(_ status: Lead.Status) {
        if var lead = existingLead {
            applyContact(to: &lead)
            if let info = property { applyProperty(info, to: &lead) }
            leadStore.update(lead)
            leadStore.setStatus(status, for: lead)
        } else {
            leadStore.add(newLead(status: status, knockedNow: true))
        }
    }
}

/// One storm report row: kind icon, magnitude, distance, date, location.
struct StormReportRow: View {
    let item: NearbyStormReport

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.report.kind.symbolName)
                .font(.title3)
                .frame(width: 30)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.report.magnitudeText)
                    .font(.subheadline.weight(.semibold))
                Text("\(item.report.location.capitalized), \(item.report.state) · \(item.report.county.capitalized) Co.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.dateFormatter.string(from: item.report.dateUTC))
                    .font(.caption.weight(.medium))
                Text(String(format: "%.1f mi", item.distanceMiles))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iconColor: Color { item.report.kind.color }
}
