import Foundation

// The swipe list — "saw it, thought of you." Spot something in the feed a
// friend might love, add it here, then send the list so they swipe yes/no on
// it. Local-first (like pools); server sync attaches once friend graphs land.
@MainActor
final class SwipeListStore: ObservableObject {
    static let shared = SwipeListStore()

    @Published private(set) var posts: [Post] = []

    private static let storageKey = "giftmaxxing_swipe_list"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([Post].self, from: data) {
            posts = saved
        }
    }

    func contains(_ post: Post) -> Bool {
        posts.contains(where: { $0.id == post.id })
    }

    // Toggle: tapping again removes (undo without a separate manage screen).
    func toggle(_ post: Post) {
        if let idx = posts.firstIndex(where: { $0.id == post.id }) {
            posts.remove(at: idx)
        } else {
            posts.insert(post, at: 0)
            AnalyticsEngine.shared.trackScreenView(screen: "swipe_list_add")
        }
        persist()
    }

    func remove(id: String) {
        posts.removeAll(where: { $0.id == id })
        persist()
    }

    // Share text for sending the list to a friend.
    var shareMessage: String {
        let names = posts.prefix(5).map { "• \($0.product.name)" }.joined(separator: "\n")
        let more = posts.count > 5 ? "\n…and \(posts.count - 5) more" : ""
        return "I made you a gift swipe list 🎁 Swipe yes/no on these:\n\(names)\(more)\n\nOn Giftmaxxing"
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(posts) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
