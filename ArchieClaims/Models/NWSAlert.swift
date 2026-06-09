import Foundation

/// An active National Weather Service alert for a point, from api.weather.gov.
struct NWSAlert: Identifiable, Hashable {
    let id: String
    let event: String
    let headline: String?
    let severity: String?
    let onset: Date?
    let ends: Date?
    let areaDesc: String?
    let instruction: String?
}

/// Minimal decoding of the NWS `/alerts/active?point=` GeoJSON response.
struct NWSAlertResponse: Decodable {
    struct Feature: Decodable {
        struct Properties: Decodable {
            let id: String?
            let event: String?
            let headline: String?
            let severity: String?
            let onset: String?
            let ends: String?
            let areaDesc: String?
            let instruction: String?
        }
        let properties: Properties
    }
    let features: [Feature]

    var alerts: [NWSAlert] {
        let iso = ISO8601DateFormatter()
        return features.compactMap { feature in
            let p = feature.properties
            guard let event = p.event else { return nil }
            return NWSAlert(
                id: p.id ?? UUID().uuidString,
                event: event,
                headline: p.headline,
                severity: p.severity,
                onset: p.onset.flatMap { iso.date(from: $0) },
                ends: p.ends.flatMap { iso.date(from: $0) },
                areaDesc: p.areaDesc,
                instruction: p.instruction
            )
        }
    }
}
