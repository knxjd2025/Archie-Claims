import Foundation
import CoreLocation
import Contacts

/// Geocodes between addresses and coordinates using Apple's CLGeocoder
/// (no extra API key required): reverse for tapped rooftops, forward for the
/// map search field (full addresses or just a city).
enum GeocodingService {

    struct Result {
        let address: String
        let city: String
        let state: String
        let postalCode: String
        let county: String
    }

    /// A forward-geocoded match for a typed address or city.
    struct Place: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let coordinate: CLLocationCoordinate2D
        /// Suggested camera span: tight for street addresses, wide for cities.
        let spanDegrees: Double
        let isSpecificAddress: Bool
    }

    /// Forward-geocodes a typed query ("123 Main St Charlotte" or "Denver CO").
    static func geocode(_ query: String) async -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let geocoder = CLGeocoder()
        guard let placemarks = try? await geocoder.geocodeAddressString(trimmed) else {
            return []
        }
        return placemarks.compactMap { placemark in
            guard let coordinate = placemark.location?.coordinate else { return nil }
            let isAddress = placemark.subThoroughfare != nil || placemark.thoroughfare != nil
            let span: Double
            if let circle = placemark.region as? CLCircularRegion {
                // Radius (m) → degrees of latitude, padded for context.
                span = max(0.003, min(2.5, circle.radius * 2.4 / 111_000))
            } else {
                span = isAddress ? 0.004 : 0.15
            }
            let subtitle = [placemark.locality, placemark.administrativeArea, placemark.postalCode]
                .compactMap { $0 }
                .joined(separator: ", ")
            return Place(
                title: placemark.name ?? placemark.locality ?? trimmed,
                subtitle: subtitle,
                coordinate: coordinate,
                spanDegrees: span,
                isSpecificAddress: isAddress
            )
        }
    }

    static func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> Result? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return nil
        }

        let formatted: String
        if let postal = placemark.postalAddress {
            formatted = CNPostalAddressFormatter.string(from: postal, style: .mailingAddress)
                .replacingOccurrences(of: "\n", with: ", ")
        } else {
            formatted = [placemark.name, placemark.locality, placemark.administrativeArea, placemark.postalCode]
                .compactMap { $0 }
                .joined(separator: ", ")
        }

        return Result(
            address: formatted,
            city: placemark.locality ?? "",
            state: placemark.administrativeArea ?? "",
            postalCode: placemark.postalCode ?? "",
            county: placemark.subAdministrativeArea ?? ""
        )
    }
}
