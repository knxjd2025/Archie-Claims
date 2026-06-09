import Foundation
import SwiftUI

/// App-wide user preferences. The Anthropic API key is intentionally NOT here —
/// it lives in the Keychain (see `KeychainStore`).
enum AppSettings {
    /// Identifies the app to NOAA/NWS APIs per their User-Agent guidance.
    /// Replace with your real support address before release.
    static let contactEmailForAPIs = "support@example.com"

    static let searchRadiusKey = "settings.searchRadiusMiles"
    static let lookbackDaysKey = "settings.lookbackDays"
    static let modelOverrideKey = "settings.modelOverride"
    static let proxyBaseURLKey = "settings.proxyBaseURL"
    static let onboardingDoneKey = "settings.onboardingDone"

    static let defaultRadiusMiles: Double = 10
    static let defaultLookbackDays: Int = 30

    /// Effective model id for the assistant (defaults to Claude Opus 4.8).
    static func model(from override: String) -> String {
        let trimmed = override.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? ClaudeService.defaultModel : trimmed
    }

    /// Effective API base URL (defaults to api.anthropic.com; teams may proxy).
    static func baseURL(from override: String) -> URL {
        let trimmed = override.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme == "https" else {
            return ClaudeService.defaultBaseURL
        }
        return url
    }
}
