import Foundation
import CoreLocation

/// Free property characteristics for a tapped house, from OpenStreetMap's
/// Nominatim reverse-geocoder (no API key). Fills in what's publicly mapped —
/// building type, number of stories, roof shape/material. Owner identity is NOT
/// available here; that comes from the paid owner-report lookup.
enum PropertyDataService {

    struct PropertyInfo: Equatable {
        var propertyType: String?   // e.g. "house", "Residential"
        var stories: Int?           // building:levels
        var roofShape: String?      // e.g. "gable", "hip"
        var roofMaterial: String?   // e.g. "asphalt", "metal"

        /// True when at least one useful field was found.
        var hasAny: Bool {
            propertyType != nil || stories != nil || roofShape != nil || roofMaterial != nil
        }

        /// One-line summary for AI context / lead notes.
        var summary: String? {
            var parts: [String] = []
            if let propertyType { parts.append(propertyType.capitalized) }
            if let stories { parts.append("\(stories) stor\(stories == 1 ? "y" : "ies")") }
            if let roofShape { parts.append("\(roofShape) roof") }
            if let roofMaterial { parts.append(roofMaterial) }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
    }

    private static var userAgent: String {
        "ArchieClaims/1.0 (roofing canvassing app; \(AppSettings.contactEmailForAPIs))"
    }

    /// Reverse-geocodes a coordinate into mapped property characteristics.
    /// Returns nil on network failure or when nothing useful is mapped.
    static func lookup(_ coordinate: CLLocationCoordinate2D) async -> PropertyInfo? {
        let lat = String(format: "%.6f", coordinate.latitude)
        let lon = String(format: "%.6f", coordinate.longitude)
        guard let url = URL(string:
            "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=\(lat)&lon=\(lon)&zoom=18&addressdetails=1&extratags=1"
        ) else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(NominatimReverse.self, from: data)

            var info = PropertyInfo()
            let extra = decoded.extratags ?? [:]

            // Building type: prefer an explicit building tag, else the place type.
            if let building = extra["building"], building != "yes" {
                info.propertyType = humanize(building)
            } else if let type = decoded.type, ["house", "residential", "apartments", "detached", "terrace"].contains(type) {
                info.propertyType = humanize(type)
            }
            if let levels = extra["building:levels"], let n = Int(levels.prefix(while: { $0.isNumber })) {
                info.stories = n
            }
            if let shape = extra["roof:shape"] { info.roofShape = humanize(shape) }
            if let material = extra["roof:material"] { info.roofMaterial = humanize(material) }

            return info.hasAny ? info : nil
        } catch {
            return nil
        }
    }

    private static func humanize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
    }

    private struct NominatimReverse: Decodable {
        let type: String?
        let extratags: [String: String]?
    }
}
