import Foundation

// Thoughtfulness Points — the gamification ledger. Points reward the SLOW
// parts of gifting (writing why a gift fits, planning weeks ahead, choosing
// independent makers), not volume. Local-first like the other stores; the
// ledger doubles as the data source for badges, the profile stats, and the
// Circles gift streak.
struct ThoughtfulnessBadge: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let icon: String
    let detail: String
    var earnedAt: Date
}

@MainActor
final class ThoughtfulnessStore: ObservableObject {
    static let shared = ThoughtfulnessStore()

    enum Action: String, Codable {
        case noteWritten = "note_written"           // wrote why a gift fits (+15)
        case letterWritten = "letter_written"       // wrote a digital gift letter (+40)
        case boardCreated = "board_created"         // started a Gift Board (+10)
        case boardShared = "board_shared"           // sent a board to its person (+25)
        case smallBusinessSave = "small_business"   // saved an independent-maker find (+8)
        case earlyPlanning = "early_planning"       // planned ≥2 weeks ahead (+30)
        case poolStarted = "pool_started"           // opened a gift pool (+20)

        var points: Int {
            switch self {
            case .noteWritten: return 15
            case .letterWritten: return 40
            case .boardCreated: return 10
            case .boardShared: return 25
            case .smallBusinessSave: return 8
            case .earlyPlanning: return 30
            case .poolStarted: return 20
            }
        }
    }

    struct Event: Codable {
        let kind: Action
        let at: Date
    }

    @Published private(set) var points = 0
    @Published private(set) var badges: [ThoughtfulnessBadge] = []
    private(set) var events: [Event] = []
    private var dedupeKeys = Set<String>()

    private static let storageKey = "giftmaxxing_thoughtfulness"

    private struct Persisted: Codable {
        var points: Int
        var events: [Event]
        var badges: [ThoughtfulnessBadge]
        var dedupeKeys: [String]
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(Persisted.self, from: data) {
            points = saved.points
            events = saved.events
            badges = saved.badges
            dedupeKeys = Set(saved.dedupeKeys)
        }
    }

    // Award an action. `dedupeKey` makes an award once-only (e.g. one
    // early-planning award per event, one note award per item).
    func award(_ action: Action, dedupeKey: String? = nil) {
        if let dedupeKey {
            let key = "\(action.rawValue)|\(dedupeKey)"
            guard dedupeKeys.insert(key).inserted else { return }
        }
        points += action.points
        events.append(Event(kind: action, at: Date()))
        refreshBadges()
        persist()
    }

    // Consecutive calendar months (ending now) with at least one thoughtful
    // action — the Circles "gift streak".
    var monthlyStreak: Int {
        let calendar = Calendar.current
        let months = Set(events.map { calendar.dateComponents([.year, .month], from: $0.at) })
        var streak = 0
        var cursor = Date()
        while months.contains(calendar.dateComponents([.year, .month], from: cursor)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .month, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    private func count(_ action: Action) -> Int {
        events.filter { $0.kind == action }.count
    }

    // Badge catalog — earned once, kept forever.
    private func refreshBadges() {
        let rules: [(id: String, name: String, icon: String, detail: String, earned: Bool)] = [
            ("storyteller", "Storyteller", "text.quote",
             "Wrote your first gift note", count(.noteWritten) >= 1),
            ("letter-writer", "Letter writer", "envelope.open.fill",
             "Wrote a digital gift letter", count(.letterWritten) >= 1),
            ("curator", "Curator", "square.grid.2x2.fill",
             "Keeps 3+ Gift Boards", count(.boardCreated) >= 3),
            ("early-bird", "Early bird", "sunrise.fill",
             "Planned a gift 2+ weeks ahead", count(.earlyPlanning) >= 1),
            ("small-biz-champion", "Small-business champion", "storefront.fill",
             "Saved 5 independent-maker finds", count(.smallBusinessSave) >= 5),
            ("gift-captain", "Gift captain", "person.3.fill",
             "Rallied a group gift", count(.poolStarted) >= 1),
        ]
        for rule in rules where rule.earned && !badges.contains(where: { $0.id == rule.id }) {
            badges.append(ThoughtfulnessBadge(
                id: rule.id, name: rule.name, icon: rule.icon, detail: rule.detail, earnedAt: Date()
            ))
        }
    }

    // Account boundary (AccountLocalState): the ledger is personal — wiped on
    // sign-out / account switch.
    func clear() {
        points = 0
        events = []
        badges = []
        dedupeKeys = []
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        let payload = Persisted(
            points: points, events: events, badges: badges, dedupeKeys: Array(dedupeKeys)
        )
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
