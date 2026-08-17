import Foundation
import UserNotifications
import GiftmaxxingCore

// Local reminders for gift events — the on-device half of the reminders story.
// The backend job (infra/src/reminders.mjs) publishes server-side nudges to an
// SNS topic; this scheduler guarantees the user gets a notification even with
// push disabled or the server dark: pure UNUserNotificationCenter, no network.
//
// Contract mirrors the server: fire at `reminderLeadDays` before the event
// (default 7, same as reminders.mjs) and again on the day itself. Notification
// ids are namespaced `evt_<eventId>_lead` / `evt_<eventId>_day` so a resync can
// sweep stale ones without touching other notifications (pools, challenges).
enum ReminderScheduler {
    static let defaultLeadDays = 7

    private static let idPrefix = "evt_"

    // One-tap lead-time choices for the add-event sheet.
    static let leadChoices: [(days: Int, label: String)] = [
        (0, "Day of"),
        (1, "1 day before"),
        (3, "3 days before"),
        (7, "1 week before"),
        (14, "2 weeks before"),
    ]

    static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    // Replace this event's pending reminders with fresh ones.
    static func schedule(for event: GiftEvent) {
        cancel(eventId: event.id)
        guard event.daysUntil >= 0 else { return }

        // Events with real runway also get the staged Gift Journey
        // (explore → narrow → letter → send) — Maxi's paced nudges.
        GiftJourneyEngine.schedule(for: event)

        let lead = event.reminderLeadDays ?? defaultLeadDays
        let calendar = Calendar.current
        let eventDay = calendar.startOfDay(for: event.date)
        let who = event.recipientName.isEmpty ? event.title : event.recipientName

        var requests: [(id: String, date: Date, title: String, body: String)] = []

        // Lead-time nudge — enough runway to actually get a gift shipped.
        if lead > 0,
           let leadDate = calendar.date(byAdding: .day, value: -lead, to: eventDay),
           at(hour: 9, of: leadDate) > Date() {
            requests.append((
                id: "\(idPrefix)\(event.id)_lead",
                date: at(hour: 9, of: leadDate),
                title: "\(event.title) in \(lead) \(lead == 1 ? "day" : "days")",
                body: "Time to sort the gift for \(who) — Maxi has ideas."
            ))
        }

        // Day-of — never let the date itself slip by.
        if at(hour: 9, of: eventDay) > Date() {
            requests.append((
                id: "\(idPrefix)\(event.id)_day",
                date: at(hour: 9, of: eventDay),
                title: "Today: \(event.title)",
                body: "It's \(who)'s big day 🎁"
            ))
        }

        let center = UNUserNotificationCenter.current()
        for req in requests {
            let content = UNMutableNotificationContent()
            content.title = req.title
            content.body = req.body
            content.sound = .default
            content.userInfo = ["type": "event_reminder", "eventId": event.id]

            let components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: req.date
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: req.id, content: content, trigger: trigger))
        }
    }

    static func cancel(eventId: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [
            "\(idPrefix)\(eventId)_lead",
            "\(idPrefix)\(eventId)_day",
        ])
        GiftJourneyEngine.cancel(eventId: eventId)
    }

    // Full resync after a server fetch: drop every event reminder we own, then
    // reschedule from the fresh list — deletions on other devices propagate.
    static func resync(events: [GiftEvent]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let stale = pending.map(\.identifier).filter {
                $0.hasPrefix(idPrefix) || $0.hasPrefix(GiftJourneyEngine.idPrefix)
            }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            for event in events {
                schedule(for: event)
            }
        }
    }

    private static func at(hour: Int, of day: Date) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }
}
