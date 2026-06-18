import Foundation
import CoreLocation
import SwiftUI

/// A canvassing lead: one door, one homeowner conversation.
struct Lead: Identifiable, Codable, Hashable {
    enum Status: String, Codable, CaseIterable, Identifiable {
        case newLead = "New"
        case notHome = "Not Home"
        case interested = "Interested"
        case appointment = "Appointment"
        case inspected = "Inspected"
        case signed = "Signed"
        case notInterested = "Not Interested"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .newLead: return "mappin.circle.fill"
            case .notHome: return "door.left.hand.closed"
            case .interested: return "hand.thumbsup.fill"
            case .appointment: return "calendar.badge.clock"
            case .inspected: return "checkmark.seal.fill"
            case .signed: return "signature"
            case .notInterested: return "hand.thumbsdown.fill"
            }
        }

        /// Canonical status color, shared by map pins and the leads list.
        var color: Color {
            switch self {
            case .newLead: return .blue
            case .notHome: return .gray
            case .interested: return .orange
            case .appointment: return .purple
            case .inspected: return .teal
            case .signed: return .green
            case .notInterested: return .red
            }
        }

        /// Wire value sent to the CRM sync endpoint (matches the server's
        /// canvass-status-map: 'new', 'not_home', 'interested', …).
        var wireValue: String {
            switch self {
            case .newLead: return "new"
            case .notHome: return "not_home"
            case .interested: return "interested"
            case .appointment: return "appointment"
            case .inspected: return "inspected"
            case .signed: return "signed"
            case .notInterested: return "not_interested"
            }
        }

        /// Statuses that become a CRM pipeline lead (vs. a door-knock only).
        var isQualifiedLead: Bool {
            switch self {
            case .interested, .appointment, .inspected, .signed: return true
            case .newLead, .notHome, .notInterested: return false
            }
        }
    }

    /// CRM sync lifecycle for a lead. Optional on the model so leads saved before
    /// sync existed decode to nil (treated as `.local`, i.e. needs sending).
    enum SyncState: String, Codable {
        case local      // created on device, never sent
        case queued     // edited since last sync, waiting to send
        case syncing    // request in flight
        case synced     // the CRM acknowledged this door
        case failed     // last attempt errored; will retry
    }

    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var status: Status
    var address: String
    var latitude: Double
    var longitude: Double
    var homeownerName: String
    var phone: String
    var notes: String
    /// Snapshot of the best nearby storm evidence at the time the lead was saved.
    var stormSummary: String
    /// Homeowner email (manual entry or paid owner report). Optional default so
    /// older saved leads migrate cleanly.
    var email: String = ""
    /// Free property characteristics auto-filled from OpenStreetMap.
    var propertyType: String? = nil
    var stories: Int? = nil
    var roofShape: String? = nil
    /// When a door was actually knocked (created or status changed) — drives the
    /// "today" tally so editing notes on an old lead doesn't inflate door counts.
    /// Optional for migration: leads saved before this field decode to nil and
    /// fall back to `updatedAt`.
    var lastKnockAt: Date?

    /// Rep-applied quick tags for triage ("Roof damage", "Dog", "Callback"…).
    /// A device-side canvassing aid; not sent to the CRM. Defaulted for migration.
    var tags: [String] = []

    /// When the rep plans to come back. Drives the Follow-ups list and a local
    /// reminder notification. Device-side; not sent to the CRM. Defaulted for migration.
    var followUpAt: Date? = nil

    /// The timestamp that counts as a knock for tallies.
    var knockedAt: Date { lastKnockAt ?? updatedAt }

    /// A follow-up exists and its time has arrived (or passed).
    var isFollowUpDue: Bool {
        guard let followUpAt else { return false }
        return followUpAt <= Date()
    }

    // MARK: - Tag catalog

    /// Curated quick-pick tags shown as chips. Reps can also add custom ones.
    static let suggestedTags: [String] = [
        "Roof damage", "Active leak", "Old roof", "Insurance filed",
        "Competitor", "Renter", "Dog", "Callback", "Do not knock"
    ]

    /// SF Symbol + color for a tag chip. Known tags get distinct styling;
    /// custom tags fall back to a neutral label.
    static func tagStyle(_ tag: String) -> (symbol: String, color: Color) {
        switch tag {
        case "Roof damage": return ("exclamationmark.triangle.fill", .red)
        case "Active leak": return ("drop.fill", .blue)
        case "Old roof": return ("clock.arrow.circlepath", .orange)
        case "Insurance filed": return ("doc.text.fill", .teal)
        case "Competitor": return ("flag.fill", .purple)
        case "Renter": return ("person.fill", .gray)
        case "Dog": return ("pawprint.fill", .brown)
        case "Callback": return ("phone.arrow.up.right.fill", .indigo)
        case "Do not knock": return ("hand.raised.fill", .red)
        default: return ("tag.fill", .gray)
        }
    }

    // MARK: - CRM sync (managed by LeadSyncService; all optional for migration)

    /// Current sync lifecycle state (nil = never synced → treated as `.local`).
    var syncState: SyncState? = nil
    /// The CRM `leads.id` once this door became a qualified lead.
    var syncedCRMLeadID: String? = nil
    /// The CRM `door_knocks.id` for this door.
    var syncedKnockID: String? = nil
    var lastSyncAttempt: Date? = nil
    /// Last per-item error string from the server (when `.failed`).
    var syncError: String? = nil

    var effectiveSyncState: SyncState { syncState ?? .local }

    /// True when this door still needs to be pushed to the CRM.
    var needsSync: Bool {
        switch effectiveSyncState {
        case .synced, .syncing: return false
        case .local, .queued, .failed: return true
        }
    }

    /// Deep link to this lead in the web CRM, once it has a CRM id.
    var crmURL: URL? {
        guard let id = syncedCRMLeadID else { return nil }
        return URL(string: "https://app.archie.now/leads/\(id)")
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var shortAddress: String {
        address.components(separatedBy: ",").first ?? address
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        status: Status = .newLead,
        address: String,
        latitude: Double,
        longitude: Double,
        homeownerName: String = "",
        phone: String = "",
        notes: String = "",
        stormSummary: String = "",
        lastKnockAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.homeownerName = homeownerName
        self.phone = phone
        self.notes = notes
        self.stormSummary = stormSummary
        self.lastKnockAt = lastKnockAt
    }
}
