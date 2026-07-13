import Foundation

// A named swipe list — "saw it, thought of you", per PERSON. Like Instagram's
// bookmark collections: you keep several ("Sarah's birthday", "Dad — retirement"),
// add finds from the feed or search into whichever fits, then send one as a
// swipe deck. The recipient swipes yes/no on exactly those items — direct
// buy/don't-buy signals for the giver.
struct SwipeList: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var recipientName: String?
    var occasion: String?
    var createdAt: Date = Date()
    var posts: [Post] = []

    // Sharing state — set once the list has been sent as a swipe deck. The
    // link goes stale the moment the list's CONTENTS change, not just its
    // count, so the exact item set it was built for rides along.
    var challengeId: String?
    var shareURLString: String?
    var sharedContentsKey: String?

    var contentsKey: String { posts.map(\.id).joined(separator: "|") }
    var shareURL: URL? {
        guard let shareURLString, sharedContentsKey == contentsKey else { return nil }
        return URL(string: shareURLString)
    }
}

// Local-first (like pools); each list's share link is backed by a server-side
// challenge, and responses flow back through the existing challenge/connection
// surfaces.
@MainActor
final class SwipeListStore: ObservableObject {
    static let shared = SwipeListStore()

    @Published private(set) var lists: [SwipeList] = []

    private static let storageKey = "giftmaxxing_swipe_lists"
    private static let legacyStorageKey = "giftmaxxing_swipe_list"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([SwipeList].self, from: data) {
            lists = saved
        } else if let data = UserDefaults.standard.data(forKey: Self.legacyStorageKey),
                  let savedPosts = try? JSONDecoder().decode([Post].self, from: data),
                  !savedPosts.isEmpty {
            // One-time migration: the old single flat list becomes the first
            // named list so nothing anyone saved disappears.
            lists = [SwipeList(name: "My swipe list", posts: savedPosts)]
            persist()
        }
    }

    // Every saved post across lists, newest-list-first, deduped — feeds the
    // challenge seed picker and any "is it saved anywhere?" check.
    var allPosts: [Post] {
        var seen = Set<String>()
        return lists.flatMap(\.posts).filter { seen.insert($0.id).inserted }
    }

    func contains(_ post: Post) -> Bool {
        lists.contains { list in list.posts.contains(where: { $0.id == post.id }) }
    }

    func listIds(containing postId: String) -> Set<String> {
        Set(lists.filter { $0.posts.contains(where: { $0.id == postId }) }.map(\.id))
    }

    func list(id: String) -> SwipeList? {
        lists.first(where: { $0.id == id })
    }

    @discardableResult
    func createList(name: String, recipientName: String? = nil, occasion: String? = nil) -> SwipeList {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let recipient = recipientName?.trimmingCharacters(in: .whitespaces)
        let list = SwipeList(
            name: trimmed.isEmpty ? "New swipe list" : trimmed,
            recipientName: (recipient?.isEmpty ?? true) ? nil : recipient,
            occasion: occasion
        )
        lists.insert(list, at: 0)
        persist()
        AnalyticsEngine.shared.trackScreenView(screen: "swipe_list_create")
        return list
    }

    func deleteList(id: String) {
        let removed = lists.first(where: { $0.id == id })?.posts ?? []
        lists.removeAll(where: { $0.id == id })
        persist()
        for post in removed where !contains(post) {
            recordTasteEvent(for: post, removed: true)
        }
    }

    // Toggle membership of one post in one list (tapping again removes —
    // undo without a separate manage screen, same contract as before).
    func toggle(_ post: Post, in listId: String) {
        guard let idx = lists.firstIndex(where: { $0.id == listId }) else { return }
        let wasAnywhere = contains(post)
        if let postIdx = lists[idx].posts.firstIndex(where: { $0.id == post.id }) {
            lists[idx].posts.remove(at: postIdx)
        } else {
            lists[idx].posts.insert(post, at: 0)
            AnalyticsEngine.shared.trackScreenView(screen: "swipe_list_add")
        }
        persist()

        // "Saw it, thought of you" is a labeled (item × giver × intended-friend)
        // gift-intent triple nothing else captures — fold it into taste tagged
        // GIFT-MODE, but only when the post enters/leaves the store as a whole
        // (membership in a second list isn't a second signal).
        let isAnywhere = contains(post)
        if wasAnywhere != isAnywhere {
            recordTasteEvent(for: post, removed: !isAnywhere)
        }
    }

    func remove(id postId: String, from listId: String) {
        guard let idx = lists.firstIndex(where: { $0.id == listId }) else { return }
        guard let post = lists[idx].posts.first(where: { $0.id == postId }) else { return }
        lists[idx].posts.removeAll(where: { $0.id == postId })
        persist()
        if !contains(post) {
            recordTasteEvent(for: post, removed: true)
        }
    }

    // Record the share link (and the exact contents it was built for) so the
    // list can keep offering the same URL until its items change.
    func markShared(listId: String, challengeId: String, url: URL) {
        guard let idx = lists.firstIndex(where: { $0.id == listId }) else { return }
        lists[idx].challengeId = challengeId
        lists[idx].shareURLString = url.absoluteString
        lists[idx].sharedContentsKey = lists[idx].contentsKey
        persist()
    }

    // Share text for sending a list to its person.
    func shareMessage(for list: SwipeList) -> String {
        let who = list.recipientName ?? "you"
        return "I made \(who) a gift swipe list 🎁 Swipe yes/no on \(list.posts.count) picks — takes a minute.\n\nOn Giftmaxxing"
    }

    private func recordTasteEvent(for post: Post, removed: Bool) {
        let kind: TasteEvent.Kind = removed ? .queueRemove : .queueAdd
        Task {
            let signals = TasteSignals.extract(from: post)
            await TasteProfileStore.shared.record(TasteEvent(
                kind: kind,
                postId: post.id,
                author: post.user,
                price: post.product.price,
                vibes: signals.vibes,
                category: signals.category,
                giftType: post.giftType ?? "product"
            ))
            await InteractionQueue.shared.enqueue(
                userId: nil,
                targetId: post.id,
                type: removed ? "queue_remove" : "queue_add",
                data: ["mode": "gift", "giftType": post.giftType ?? "product"]
            )
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(lists) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
