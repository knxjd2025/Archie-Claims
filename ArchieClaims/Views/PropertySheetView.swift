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

    @State private var geocode: GeocodingService.Result?
    @State private var geocodeFailed = false
    @State private var stormLoadState: LoadState = .loading
    @State private var nearbyReports: [NearbyStormReport] = []
    @State private var alerts: [NWSAlert] = []
    @State private var safariURL: IdentifiableURL?

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
                stormSection
                contactSection
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
            .task {
                async let geo: Void = loadGeocode()
                async let storms: Void = loadStorms()
                _ = await (geo, storms)
            }
            .sheet(item: $safariURL) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
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

            Button {
                openInMaps()
            } label: {
                Label("Open in Apple Maps", systemImage: "map")
            }
        }
    }

    private func openInMaps() {
        let query = (geocode?.address ?? "\(coordinate.latitude),\(coordinate.longitude)")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "http://maps.apple.com/?ll=\(coordinate.latitude),\(coordinate.longitude)&q=\(query)"
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
                }
            }
        } header: {
            Text("Storm Evidence — \(Int(radiusMiles)) mi / \(AppSettings.lookbackLabel(days: lookbackDays))")
        } footer: {
            Text("Source: NOAA Storm Prediction Center reports & National Weather Service alerts. Preliminary, unverified data.")
        }
    }

    private var contactSection: some View {
        Section {
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
            Text("Owner & Contact Lookup (Free Public Sources)")
        } footer: {
            Text(PublicRecordsLinks.complianceNote)
        }
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
        "Storm report for \(addressLine)\n\(stormSummary)\n\nGenerated with Archie Claims (data: NOAA SPC/NWS, preliminary)."
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

    private func saveLead() {
        if var lead = existingLead {
            lead.stormSummary = stormSummary
            leadStore.update(lead)
        } else {
            leadStore.add(Lead(
                address: addressLine,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                stormSummary: stormSummary
            ))
        }
    }

    /// Logs a door outcome from the evidence view — creates or updates the lead
    /// and stamps the knock so it counts toward today's tally.
    private func logDoor(_ status: Lead.Status) {
        if let lead = existingLead {
            leadStore.setStatus(status, for: lead)
        } else {
            leadStore.add(Lead(
                status: status,
                address: addressLine,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                stormSummary: stormSummary,
                lastKnockAt: Date()
            ))
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
