import Foundation
import SwiftUI

/// App-wide user preferences. Credentials are intentionally NOT here —
/// they live in the Keychain (see `KeychainStore`).
enum AppSettings {
    /// Identifies the app to NOAA/NWS APIs per their User-Agent guidance.
    static let contactEmailForAPIs = "support@archie.now"

    static let searchRadiusKey = "settings.searchRadiusMiles"
    static let lookbackDaysKey = "settings.lookbackDays"
    static let onboardingDoneKey = "settings.onboardingDone"
    static let archieBaseURLKey = "settings.archieBaseURL"
    /// Last map camera region, so the app reopens where the rep left off.
    static let lastCameraLatKey = "settings.lastCameraLat"
    static let lastCameraLonKey = "settings.lastCameraLon"
    static let lastCameraSpanKey = "settings.lastCameraSpan"

    static let defaultRadiusMiles: Double = 10
    static let defaultLookbackDays: Int = 30
    /// SPC daily files are fetched per convective day; cap the walk-back at 2 years.
    static let maxLookbackDays = 730
    static let lookbackPresets = [7, 14, 30, 60, 90, 180, 365, 730]

    /// Human label for a lookback window ("30 days", "6 months", "2 years").
    static func lookbackLabel(days: Int) -> String {
        switch days {
        case 180: return "6 months"
        case 365: return "1 year"
        case 730: return "2 years"
        default: return "\(days) days"
        }
    }

    /// Effective Archie backend base URL (defaults to the production Render service).
    static func archieBaseURL(from override: String) -> URL {
        let trimmed = override.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme == "https" else {
            return ArchieBackendService.defaultBaseURL
        }
        return url
    }

}
