import Foundation

// Recent searches, per device.
//
// A search page with an empty box and nothing else is a dead end — the whole
// point of the recents list is that the second visit costs one tap instead of
// retyping. Kept local: a search history names the people and occasions you
// shop for, so it is wiped on sign-out with the other private stores.
@MainActor
final class RecentSearchStore: ObservableObject {
    static let shared = RecentSearchStore()

    private static let key = "giftmaxxing_recent_searches"
    private static let maxItems = 8

    @Published private(set) var items: [String] = []

    private init() {
        items = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    func record(_ raw: String) {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return }
        // Case-insensitive dedupe, most recent first.
        items.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        items.insert(term, at: 0)
        if items.count > Self.maxItems { items.removeLast(items.count - Self.maxItems) }
        persist()
    }

    func remove(_ term: String) {
        items.removeAll { $0 == term }
        persist()
    }

    func clear() {
        items = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    private func persist() {
        UserDefaults.standard.set(items, forKey: Self.key)
    }
}
