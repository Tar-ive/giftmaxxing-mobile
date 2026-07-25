import Foundation
import UserNotifications

// The birthday → swipe-challenge journey, as local notifications re-derived
// on every Circles load (same resync pattern as ReminderScheduler): each
// step's copy is computed from the CURRENT challenge state, so reminders
// stay truthful as long as the app is opened between fires.
//
//   D-14  batched heads-up: "Sarah and Maya's birthdays are coming up —
//         send them a swipe challenge" (tap → auto-created challenge)
//   D-7   state-aware nudge
//   D-3/2/1  countdown; once their challenge is completed but the results
//         are unseen → "see the results and send the gift"
enum BirthdayChallengeJourney {
    struct Person {
        let key: String     // stable id (event id / circle member id)
        let name: String
        let birthday: Date  // NEXT occurrence, start of day
        var challengeSent = false
        var completedUnseen = false
    }

    private static let idPrefix = "bday_"
    private static let fireHour = 9

    // ── Sent-challenge memory (client-side) ──────────────────────────────
    // /connections only materializes AFTER the recipient responds, so
    // "challenge sent, awaiting swipes" is tracked locally at create time.
    private static let sentKey = "giftmaxxing_birthday_challenges_sent"

    static func recordSentChallenge(recipientName: String) {
        guard !recipientName.isEmpty else { return }
        var names = Set(UserDefaults.standard.stringArray(forKey: sentKey) ?? [])
        names.insert(recipientName.lowercased())
        UserDefaults.standard.set(Array(names), forKey: sentKey)
    }

    static func sentChallengeNames() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: sentKey) ?? [])
    }

    // ── Scheduling ────────────────────────────────────────────────────────

    static func resync(people: [Person]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard !people.isEmpty else { return }
        let calendar = Calendar.current

        // D-14 heads-up, batched: everyone whose heads-up lands on the same
        // day shares one notification ("Sarah and Maya's birthdays…").
        var headsUp: [Date: [Person]] = [:]
        for person in people {
            guard let day = calendar.date(byAdding: .day, value: -14, to: person.birthday),
                  day > Date()
            else { continue }
            headsUp[day, default: []].append(person)
        }
        for (day, group) in headsUp {
            let names = listNames(group.map(\.name))
            schedule(
                id: "\(idPrefix)heads_\(Int(day.timeIntervalSince1970))",
                title: group.count == 1
                    ? "🎂 \(names)'s birthday is coming up"
                    : "🎂 \(names) have birthdays coming up",
                body: group.count == 1
                    ? "Send them a swipe challenge — a few swipes and you'll know exactly what to get."
                    : "Send each of them a swipe challenge — a few swipes and you'll know exactly what to get.",
                fireDay: day,
                userInfo: ["type": "birthday_challenge", "recipientName": group[0].name]
            )
        }

        // D-7 nudge + D-3/2/1 countdown, per person, state-aware.
        for person in people {
            for offset in [7, 3, 2, 1] {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: person.birthday),
                      day > Date()
                else { continue }
                let (title, body, type) = copy(for: person, daysLeft: offset)
                schedule(
                    id: "\(idPrefix)\(person.key)_\(offset)",
                    title: title,
                    body: body,
                    fireDay: day,
                    userInfo: ["type": type, "recipientName": person.name]
                )
            }
        }
    }

    // Next occurrence of a circle member's "YYYY-MM-DD" birthday.
    static func nextOccurrence(ofYMD ymd: String) -> Date? {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let calendar = Calendar.current
        return calendar.nextDate(
            after: calendar.startOfDay(for: Date()).addingTimeInterval(-1),
            matching: DateComponents(month: parts[1], day: parts[2]),
            matchingPolicy: .nextTime
        ).map { calendar.startOfDay(for: $0) }
    }

    private static func copy(for person: Person, daysLeft: Int) -> (String, String, String) {
        let title: String
        switch daysLeft {
        case 1: title = "🎂 \(person.name)'s birthday is tomorrow"
        case 7: title = "🎂 One week to \(person.name)'s birthday"
        default: title = "🎂 \(daysLeft) days to \(person.name)'s birthday"
        }
        if person.completedUnseen {
            return (
                title,
                "They finished your swipe challenge — see the results and send the gift.",
                "birthday_results"
            )
        }
        if person.challengeSent {
            return (
                title,
                "They haven't finished your swipe challenge yet — give them a nudge.",
                "birthday_challenge"
            )
        }
        return (
            title,
            "Send a swipe challenge — a few swipes and you'll know exactly what to get.",
            "birthday_challenge"
        )
    }

    private static func schedule(
        id: String,
        title: String,
        body: String,
        fireDay: Date,
        userInfo: [String: Any]
    ) {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: fireDay)
        comps.hour = fireHour
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        ))
    }

    private static func listNames(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
    }
}
