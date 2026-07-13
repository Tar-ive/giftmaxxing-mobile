import Foundation
import UserNotifications

// The AI Gift Journey — intentional gifting by design, as a MIDDLE LAYER (no
// new screens). For any event far enough out, the engine stages the process —
// explore → narrow → write the letter → send — and delivers each step as a
// local notification at the right moment. Maxi's nudges ride these steps
// instead of a floating button.
//
// Notification ids are namespaced `journey_<eventId>_<step>` so
// ReminderScheduler's resync sweep can own them alongside `evt_` reminders.
enum GiftJourneyEngine {
    struct Step {
        let kind: String       // explore | narrow | letter | send
        let title: String
        let body: String
        let date: Date
    }

    static let idPrefix = "journey_"
    // Below this lead there's no journey to pace — the plain event reminders
    // (ReminderScheduler) already cover the scramble.
    static let minimumLeadDays = 7

    // Proportional plan across the available runway: explore right away,
    // narrow at ~40%, write the letter at ~70%, send/wrap 2 days out.
    static func plan(eventId: String, title: String, who: String, eventDate: Date, from now: Date = Date()) -> [Step] {
        let calendar = Calendar.current
        let eventDay = calendar.startOfDay(for: eventDate)
        let lead = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: eventDay).day ?? 0
        guard lead >= minimumLeadDays else { return [] }

        func day(atFraction fraction: Double) -> Date {
            let offset = Int((Double(lead) * fraction).rounded())
            return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
        }

        return [
            Step(
                kind: "explore",
                title: "\(title): start exploring 🌱",
                body: "\(lead) days of runway for \(who). Browse a few ideas today — no pressure, just noticing.",
                date: day(atFraction: 0.05)
            ),
            Step(
                kind: "narrow",
                title: "\(title): narrow it down",
                body: "Pick your 3 favorites onto \(who)'s Gift Board — or send it so they swipe.",
                date: day(atFraction: 0.4)
            ),
            Step(
                kind: "letter",
                title: "\(title): write the letter ✍️",
                body: "The words outlast the wrapping. Add a gift letter to \(who)'s board.",
                date: day(atFraction: 0.7)
            ),
            Step(
                kind: "send",
                title: "\(title): time to get it",
                body: "2-day buffer for shipping or wrapping — order \(who)'s gift now.",
                date: calendar.date(byAdding: .day, value: -2, to: eventDay) ?? eventDay
            ),
        ]
    }

    // Schedule the journey for one event (idempotent: replaces its own steps).
    // Planning this early IS the thoughtful act — it earns the points.
    static func schedule(for event: GiftEvent) {
        cancel(eventId: event.id)
        let who = event.recipientName.isEmpty ? "them" : event.recipientName
        let steps = plan(eventId: event.id, title: event.title, who: who, eventDate: event.date)
        guard !steps.isEmpty else { return }

        if event.daysUntil >= 14 {
            Task { @MainActor in
                ThoughtfulnessStore.shared.award(.earlyPlanning, dedupeKey: event.id)
            }
        }

        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        for step in steps {
            let fireAt = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: step.date) ?? step.date
            guard fireAt > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = step.title
            content.body = step.body
            content.sound = .default
            content.userInfo = ["type": "gift_journey", "eventId": event.id, "step": step.kind]
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(
                identifier: "\(idPrefix)\(event.id)_\(step.kind)",
                content: content,
                trigger: trigger
            ))
        }
    }

    static func cancel(eventId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:
            ["explore", "narrow", "letter", "send"].map { "\(idPrefix)\(eventId)_\($0)" }
        )
    }
}
