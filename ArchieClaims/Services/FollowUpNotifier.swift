import Foundation
import UserNotifications

/// Schedules a local reminder for a lead's follow-up date. Entirely on-device —
/// no server involvement. Safe to call repeatedly: each reschedule cancels the
/// prior reminder for that lead first, so it always reflects the latest date.
enum FollowUpNotifier {

    /// Cancel any existing reminder for this lead, then schedule a fresh one if
    /// the lead has a future follow-up date. Requests notification permission the
    /// first time a rep sets a follow-up; if denied, the in-app Follow-ups list
    /// still works.
    static func reschedule(for lead: Lead) {
        let center = UNUserNotificationCenter.current()
        let id = identifier(for: lead.id)
        center.removePendingNotificationRequests(withIdentifiers: [id])

        guard let date = lead.followUpAt, date > Date() else { return }

        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            // Re-check: a denied prompt means no point scheduling.
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "Follow up today"
            content.body = lead.homeownerName.isEmpty
                ? lead.shortAddress
                : "\(lead.homeownerName) — \(lead.shortAddress)"
            content.sound = .default

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// Remove a lead's pending reminder (on delete or when the date is cleared).
    static func cancel(_ leadID: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(for: leadID)])
    }

    private static func identifier(for leadID: UUID) -> String {
        "followup-\(leadID.uuidString)"
    }
}
