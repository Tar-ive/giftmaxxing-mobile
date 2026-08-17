import Foundation
import UserNotifications
import GiftmaxxingNetworking
import GiftmaxxingCore

// Birthday freebies — the "free stuff on your birthday" canon (Sephora gift,
// Starbucks drink, Denny's Grand Slam...) surfaced as a Shop section.
//
// Data: GET /birthday-freebies (curated server-side, updatable without an app
// release) with a bundled fallback so the section renders offline/first-launch.
// Birthday: month/day only (no year — not needed, less sensitive), stored in
// UserDefaults. Reminders: yearly-repeating LOCAL notifications (same
// no-server-needed approach as ReminderScheduler) — one when the birthday
// month starts, one on the day itself.

@MainActor
final class BirthdayPerksStore: ObservableObject {
    static let shared = BirthdayPerksStore()

    @Published private(set) var perks: [BirthdayPerk] = BirthdayPerk.fallback
    @Published private(set) var isLive = false
    @Published var birthMonth: Int? {
        didSet { persistAndReschedule() }
    }
    @Published var birthDay: Int? {
        didSet { persistAndReschedule() }
    }

    private let monthKey = "birthday_perks_month"
    private let dayKey = "birthday_perks_day"
    private static let monthStartNotifId = "bday_perks_monthstart"
    private static let dayOfNotifId = "bday_perks_dayof"

    private init() {
        let m = UserDefaults.standard.integer(forKey: monthKey)
        let d = UserDefaults.standard.integer(forKey: dayKey)
        birthMonth = (1...12).contains(m) ? m : nil
        birthDay = (1...31).contains(d) ? d : nil
    }

    // MARK: - Data

    func load() async {
        guard !isLive else { return }
        guard let response = try? await APIClient.shared.fetchBirthdayFreebies(),
              !response.perks.isEmpty else { return }
        perks = response.perks
        isLive = true
    }

    var categories: [String] {
        var seen = Set<String>()
        return perks.map(\.category).filter { seen.insert($0).inserted }
    }

    func perks(in category: String) -> [BirthdayPerk] {
        perks.filter { $0.category == category }
    }

    // MARK: - Birthday month state

    var hasBirthday: Bool { birthMonth != nil }

    var isBirthdayMonth: Bool {
        guard let birthMonth else { return false }
        return Calendar.current.component(.month, from: Date()) == birthMonth
    }

    // "March" for the hero copy; nil when no birthday is set.
    var birthMonthName: String? {
        guard let birthMonth else { return nil }
        var comps = DateComponents()
        comps.month = birthMonth
        guard let date = Calendar.current.date(from: comps) else { return nil }
        return date.formatted(.dateTime.month(.wide))
    }

    // MARK: - Reminders (yearly-repeating local notifications)

    private func persistAndReschedule() {
        if let birthMonth {
            UserDefaults.standard.set(birthMonth, forKey: monthKey)
        } else {
            UserDefaults.standard.removeObject(forKey: monthKey)
        }
        if let birthDay {
            UserDefaults.standard.set(birthDay, forKey: dayKey)
        } else {
            UserDefaults.standard.removeObject(forKey: dayKey)
        }
        scheduleReminders()
    }

    func scheduleReminders() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [
            Self.monthStartNotifId, Self.dayOfNotifId,
        ])
        guard let birthMonth else { return }

        Task { await ReminderScheduler.requestPermissionIfNeeded() }

        // 1st of the birthday month, 9am — the month-long perks unlock.
        let monthStart = UNMutableNotificationContent()
        monthStart.title = "It's your birthday month 🎂"
        monthStart.body = "\(perks.count) brands owe you free stuff — see your birthday freebies in Shop."
        monthStart.sound = .default
        monthStart.userInfo = ["type": "birthday_freebies"]
        var monthComps = DateComponents()
        monthComps.month = birthMonth
        monthComps.day = 1
        monthComps.hour = 9
        center.add(UNNotificationRequest(
            identifier: Self.monthStartNotifId,
            content: monthStart,
            trigger: UNCalendarNotificationTrigger(dateMatching: monthComps, repeats: true)
        ))

        // The day itself, 9am — the birthday-only ones (Starbucks, Denny's...).
        if let birthDay {
            let dayOf = UNMutableNotificationContent()
            dayOf.title = "Happy birthday! 🎉"
            dayOf.body = "Today's the day — free Starbucks drink, Denny's Grand Slam, and more are live."
            dayOf.sound = .default
            dayOf.userInfo = ["type": "birthday_freebies"]
            var dayComps = DateComponents()
            dayComps.month = birthMonth
            dayComps.day = birthDay
            dayComps.hour = 9
            center.add(UNNotificationRequest(
                identifier: Self.dayOfNotifId,
                content: dayOf,
                trigger: UNCalendarNotificationTrigger(dateMatching: dayComps, repeats: true)
            ))
        }
    }
}

// Bundled fallback — a copy of the server dataset's headliners so the section
// is never empty. The live list (GET /birthday-freebies) replaces it on load;
// ids match infra/src/birthday-freebies.mjs.
extension BirthdayPerk {
    static let fallback: [BirthdayPerk] = [
        BirthdayPerk(id: "sephora", brand: "Sephora", category: "Beauty", gift: "Free birthday gift set (trial-size duo)", how: "Join Beauty Insider (free) — redeem in store or online with any purchase", window: "Your birthday month", url: "https://www.sephora.com/beauty/birthday-gift", emoji: "💄", color: "#D6003C"),
        BirthdayPerk(id: "ulta", brand: "Ulta Beauty", category: "Beauty", gift: "Free birthday gift + 2x points all month", how: "Join Ulta Rewards (free)", window: "Your birthday month", url: "https://www.ulta.com/rewards", emoji: "✨", color: "#F45C1A"),
        BirthdayPerk(id: "starbucks", brand: "Starbucks", category: "Coffee & Sweets", gift: "Free handcrafted drink or food item", how: "Starbucks Rewards member (free) — one purchase before your birthday", window: "Birthday only", url: "https://www.starbucks.com/rewards", emoji: "☕️", color: "#00704A"),
        BirthdayPerk(id: "dunkin", brand: "Dunkin'", category: "Coffee & Sweets", gift: "Free drink reward", how: "Join Dunkin' Rewards (free)", window: "Your birthday week", url: "https://www.dunkindonuts.com/en/dd-perks", emoji: "🍩", color: "#FF6E0C"),
        BirthdayPerk(id: "krispykreme", brand: "Krispy Kreme", category: "Coffee & Sweets", gift: "Free doughnut + drink", how: "Join Krispy Kreme Rewards (free)", window: "Your birthday month", url: "https://www.krispykreme.com/rewards", emoji: "🍩", color: "#1A6533"),
        BirthdayPerk(id: "dennys", brand: "Denny's", category: "Meals", gift: "Free Original Grand Slam breakfast", how: "Walk in with ID on your birthday — no signup", window: "Birthday only", url: "https://www.dennys.com", emoji: "🥞", color: "#FFC50D"),
        BirthdayPerk(id: "ihop", brand: "IHOP", category: "Meals", gift: "Free stack of Rooty Tooty pancakes", how: "Join the International Bank of Pancakes (free)", window: "Birthday only", url: "https://www.ihop.com/en/rewards", emoji: "🥞", color: "#2A5CAA"),
        BirthdayPerk(id: "chipotle", brand: "Chipotle", category: "Meals", gift: "Free chips & guac with purchase", how: "Chipotle Rewards member (free)", window: "Your birthday week", url: "https://www.chipotle.com/rewards", emoji: "🌯", color: "#A81612"),
        BirthdayPerk(id: "target", brand: "Target", category: "Retail & Fun", gift: "5% off one shopping trip", how: "Target Circle member (free)", window: "Your birthday month", url: "https://www.target.com/circle", emoji: "🎯", color: "#CC0000"),
        BirthdayPerk(id: "buildabear", brand: "Build-A-Bear", category: "Retail & Fun", gift: "Pay-your-age Birthday Treat Bear", how: "Bonus Club member (free) — redeem in workshop", window: "Your birthday month", url: "https://www.buildabear.com/birthday-treat-bear.html", emoji: "🧸", color: "#0072BC"),
        BirthdayPerk(id: "amc", brand: "AMC Theatres", category: "Retail & Fun", gift: "Free large popcorn upgrade + birthday reward", how: "AMC Stubs member (free)", window: "Your birthday month", url: "https://www.amctheatres.com/amcstubs", emoji: "🍿", color: "#D42027"),
        BirthdayPerk(id: "dairyqueen", brand: "Dairy Queen", category: "Coffee & Sweets", gift: "BOGO Blizzard birthday coupon", how: "DQ Rewards via the app (free)", window: "Your birthday month", url: "https://www.dairyqueen.com", emoji: "🍦", color: "#E4002B"),
    ]
}
