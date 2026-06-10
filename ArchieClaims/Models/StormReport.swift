import Foundation
import CoreLocation
import SwiftUI

/// A single severe-weather report from the NOAA Storm Prediction Center (SPC)
/// daily storm reports feed (hail, wind, or tornado).
struct StormReport: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case hail
        case wind
        case tornado

        var label: String {
            switch self {
            case .hail: return "Hail"
            case .wind: return "Wind"
            case .tornado: return "Tornado"
            }
        }

        var symbolName: String {
            switch self {
            case .hail: return "cloud.hail.fill"
            case .wind: return "wind"
            case .tornado: return "tornado"
            }
        }
    }

    var id: String {
        "\(kind.rawValue)-\(dateUTC.timeIntervalSince1970)-\(timeHHMM)-\(latitude)-\(longitude)-\(rawMagnitude)"
    }

    let kind: Kind
    /// The SPC "convective day" this report belongs to (12Z–12Z), stored as a UTC date.
    let dateUTC: Date
    /// Report time as reported by SPC (HHMM, local CST/CDT per SPC convention).
    let timeHHMM: String
    /// Raw magnitude column: hail size in 1/100", wind speed in mph, or tornado F/EF scale.
    let rawMagnitude: String
    let location: String
    let county: String
    let state: String
    let latitude: Double
    let longitude: Double
    let comments: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Hail size in inches, when this is a hail report with a numeric size.
    var hailSizeInches: Double? {
        guard kind == .hail, let hundredths = Double(rawMagnitude) else { return nil }
        return hundredths / 100.0
    }

    /// Wind speed in mph, when this is a wind report with a numeric speed.
    var windSpeedMPH: Double? {
        guard kind == .wind, let mph = Double(rawMagnitude) else { return nil }
        return mph
    }

    /// Human-readable magnitude, e.g. "1.75\" hail", "70 mph wind", "EF2 tornado".
    var magnitudeText: String {
        switch kind {
        case .hail:
            if let size = hailSizeInches {
                return String(format: "%.2f\" hail", size)
            }
            return "Hail (size unknown)"
        case .wind:
            if let mph = windSpeedMPH {
                return "\(Int(mph)) mph wind"
            }
            return "Damaging wind"
        case .tornado:
            let scale = rawMagnitude.uppercased()
            if scale.isEmpty || scale == "UNK" { return "Tornado" }
            return scale.hasPrefix("EF") || scale.hasPrefix("F") ? "\(scale) tornado" : "EF\(scale) tornado"
        }
    }

    /// Distance in miles from the given coordinate.
    func distanceMiles(from coordinate: CLLocationCoordinate2D) -> Double {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let there = CLLocation(latitude: latitude, longitude: longitude)
        return here.distance(from: there) / 1609.344
    }
}

extension StormReport.Kind {
    /// Canonical color for this storm kind — the single source of truth used by
    /// both the canvass map markers and the property-sheet rows so a hail report
    /// is the same color everywhere.
    var color: Color {
        switch self {
        case .hail: return .orange
        case .wind: return .blue
        case .tornado: return .red
        }
    }
}

/// A storm report paired with its distance from a property of interest.
struct NearbyStormReport: Identifiable, Hashable {
    var id: String { report.id }
    let report: StormReport
    let distanceMiles: Double
}
