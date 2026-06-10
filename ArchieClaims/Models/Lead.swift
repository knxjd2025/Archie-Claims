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
    /// When a door was actually knocked (created or status changed) — drives the
    /// "today" tally so editing notes on an old lead doesn't inflate door counts.
    /// Optional for migration: leads saved before this field decode to nil and
    /// fall back to `updatedAt`.
    var lastKnockAt: Date?

    /// The timestamp that counts as a knock for tallies.
    var knockedAt: Date { lastKnockAt ?? updatedAt }

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
