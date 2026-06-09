import Foundation
import CoreLocation
import Contacts

/// Reverse-geocodes a tapped map coordinate into a street address using
/// Apple's CLGeocoder (no extra API key required).
enum GeocodingService {

    struct Result {
        let address: String
        let city: String
        let state: String
        let postalCode: String
        let county: String
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
