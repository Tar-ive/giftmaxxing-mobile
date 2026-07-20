import Foundation

// A Gift Board — "saw it, thought of you", per PERSON. (UI name: Gift Board;
// the type keeps its original name to avoid churning every call site.) Like
// Instagram's bookmark collections: you keep several ("Sarah's birthday",
// "Dad — retirement"), add finds from the feed or search into whichever fits,
// annotate WHY each fits, write a gift letter, then send it as a swipe deck.
// The recipient swipes yes/no on exactly those items — direct buy/don't-buy
// signals for the giver.
struct SwipeList: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var recipientName: String?
    var occasion: String?
    // Relationship type — the primary edge of the gift graph (a gift for a
    // spouse is not a gift for a boss); powers GiftGraphRanker's traversal.
    var relationship: String?
    var createdAt: Date = Date()
    var posts: [Post] = []
    // Per-item "why this fits them" notes (postId → note) — the thoughtful
    // half of the board, and the one-line why on Signature Gifts.
    var notes: [String: String]?
    // The digital gift letter — words that outlast the wrapping; it rides
    // along with the board's share message.
    var letter: String?

    // Private purchase checklist — the postIds the giver has already bought.
    // Local to the giver: it never rides along in the shared swipe deck (that
    // stays a clean yes/no for the recipient), only syncs across the giver's
    // own devices via the giftBoards profile like everything else here.
    var boughtPostIds: Set<String>?

    // Sharing state — set once the board has been sent as a swipe deck. The
    // link goes stale the moment the board's CONTENTS change, not just its
    // count, so the exact item set it was built for rides along.
    var challengeId: String?
    var shareURLString: String?
    var sharedContentsKey: String?

    var contentsKey: String { posts.map(\.id).joined(separator: "|") }
    var shareURL: URL? {
        guard let shareURLString, sharedContentsKey == contentsKey else { return nil }
        return URL(string: shareURLString)
    }

    func note(for postId: String) -> String? {
        guard let note = notes?[postId], !note.isEmpty else { return nil }
        return note
    }

    func isBought(_ postId: String) -> Bool { boughtPostIds?.contains(postId) ?? false }

    // How many of the board's current items are checked off. Only counts items
    // still on the board, so removing a bought item doesn't leave a stale tally.
    var boughtCount: Int {
        guard let boughtPostIds else { return 0 }
        return posts.reduce(0) { $0 + (boughtPostIds.contains($1.id) ? 1 : 0) }
    }
}

// Local-first (like pools); each list's share link is backed by a server-side
// challenge, and responses flow back through the existing challenge/connection
// surfaces.
@MainActor
final class SwipeListStore: ObservableObject {
    static let shared = SwipeListStore()

    @Published private(set) var lists: [SwipeList] = []

    // The signed-in account boards sync to (nil = guest / signed out, local only).
    private var userId: String?
    private var syncTask: Task<Void, Never>?

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
            lists = [SwipeList(name: "My Gift Board", posts: savedPosts)]
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
            name: trimmed.isEmpty ? "New Gift Board" : trimmed,
            recipientName: (recipient?.isEmpty ?? true) ? nil : recipient,
            occasion: occasion
        )
        lists.insert(list, at: 0)
        persist()
        AnalyticsEngine.shared.trackScreenView(screen: "swipe_list_create")
        ThoughtfulnessStore.shared.award(.boardCreated, dedupeKey: list.id)
        return list
    }

    func setRelationship(_ relationship: String?, for listId: String) {
        guard let idx = lists.firstIndex(where: { $0.id == listId }) else { return }
        lists[idx].relationship = relationship
        persist()
    }

    // Per-item note ("why this fits them"). First real note per item earns
    // Thoughtfulness Points — the note IS the thoughtful act.
    func setNote(_ text: String, for postId: String, in listId: String) {
        guard let idx = lists.firstIndex(where: { $0.id == listId }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var notes = lists[idx].notes ?? [:]
        if trimmed.isEmpty {
            notes.removeValue(forKey: postId)
        } else {
            notes[postId] = String(trimmed.prefix(280))
        }
        lists[idx].notes = notes
        persist()
        if !trimmed.isEmpty {
            ThoughtfulnessStore.shared.award(.noteWritten, dedupeKey: "\(listId)|\(postId)")
            // P_Custom training label: the user typed a custom message for THIS gift.
            AnalyticsEngine.shared.trackContentAction(.customMessage, postId: postId, source: "gift_board_note")
        }
    }

    // The digital gift letter — one per board.
    func setLetter(_ text: String, for listId: String) {
        guard let idx = lists.firstIndex(where: { $0.id == listId }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lists[idx].letter = trimmed.isEmpty ? nil : String(trimmed.prefix(2000))
        persist()
        if !trimmed.isEmpty {
            ThoughtfulnessStore.shared.award(.letterWritten, dedupeKey: listId)
            // P_Custom training label: a board letter is a custom message for
            // each gift riding along with it (bounded — boards cap at 100).
            for post in lists[idx].posts.prefix(20) {
                AnalyticsEngine.shared.trackContentAction(.customMessage, postId: post.id, source: "gift_letter")
            }
        }
    }

    // Private "bought" checklist. Marking an item bought never touches taste
    // signals (buying is a keep, not an un-save) and never rides along in the
    // shared deck — it's the giver's own tracking, synced across their own
    // devices only. Toggling again unchecks it.
    func toggleBought(_ postId: String, in listId: String) {
        guard let idx = lists.firstIndex(where: { $0.id == listId }) else { return }
        var bought = lists[idx].boughtPostIds ?? []
        let nowBought = !bought.contains(postId)
        if nowBought { bought.insert(postId) } else { bought.remove(postId) }
        lists[idx].boughtPostIds = bought.isEmpty ? nil : bought
        persist()
        if nowBought {
            AnalyticsEngine.shared.trackScreenView(screen: "swipe_list_bought")
        }
    }

    func isBought(_ postId: String, in listId: String) -> Bool {
        lists.first(where: { $0.id == listId })?.isBought(postId) ?? false
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
            // Choosing an independent maker is a thoughtfulness signal.
            if GiftStory.isSmallBusiness(post) {
                ThoughtfulnessStore.shared.award(.smallBusinessSave, dedupeKey: post.id)
            }
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

    // Bulk add (pasted links) — insert only the ones not already in the board,
    // recording the same gift-mode taste signal a single tap would.
    func add(_ posts: [Post], to listId: String) {
        guard let idx = lists.firstIndex(where: { $0.id == listId }) else { return }
        var added = false
        for post in posts where !lists[idx].posts.contains(where: { $0.id == post.id }) {
            let wasAnywhere = contains(post)
            lists[idx].posts.insert(post, at: 0)
            added = true
            if GiftStory.isSmallBusiness(post) {
                ThoughtfulnessStore.shared.award(.smallBusinessSave, dedupeKey: post.id)
            }
            if !wasAnywhere { recordTasteEvent(for: post, removed: false) }
        }
        if added {
            persist()
            AnalyticsEngine.shared.trackScreenView(screen: "swipe_list_add_bulk")
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
        ThoughtfulnessStore.shared.award(.boardShared, dedupeKey: listId)
    }

    // Share text for sending a board to its person — the gift letter leads
    // when there is one (the words are the point).
    func shareMessage(for list: SwipeList) -> String {
        let who = list.recipientName ?? "you"
        var message = "I made \(who) a Gift Board 🎁 Swipe yes/no on \(list.posts.count) picks — takes a minute.\n\nOn Giftmaxxing"
        if let letter = list.letter, !letter.isEmpty {
            message = "\(letter)\n\n—\n\n\(message)"
        }
        return message
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

    // Account boundary (AccountLocalState): boards, notes, and letters are
    // private to whoever wrote them — wiped on sign-out / account switch. The
    // local wipe does NOT touch the server copy (that's what lets a re-sign-in
    // restore them).
    func clear() {
        syncTask?.cancel()
        userId = nil
        lists = []
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyStorageKey)
    }

    // MARK: - Server sync (per account, via the existing /me profile)

    // Bind boards to an account and pull that account's saved boards. Called on
    // sign-in / launch. Merges: the server copy is the cross-device source of
    // truth, but any board created locally (offline / as a guest that just
    // claimed the account) that the server doesn't have yet is kept and pushed.
    func configure(userId: String?) {
        self.userId = userId
        guard userId != nil else { return }
        Task { await hydrateFromServer() }
    }

    private func hydrateFromServer() async {
        guard let userId else { return }
        let profile = try? await APIClient.shared.fetchMe(userId: userId)
        let remote = profile?.giftBoards ?? []
        if remote.isEmpty {
            // Server has none yet — if this device has boards, back them up.
            if !lists.isEmpty { scheduleSync() }
            return
        }
        let remoteIds = Set(remote.map(\.id))
        var merged = remote
        for local in lists where !remoteIds.contains(local.id) {
            merged.insert(local, at: 0)
        }
        lists = merged
        persistLocalOnly()
        if merged.count != remote.count { scheduleSync() } // we added locals
    }

    private func scheduleSync() {
        guard userId != nil else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000) // debounce bursts
            guard !Task.isCancelled else { return }
            await self?.pushToServer()
        }
    }

    private func pushToServer() async {
        guard let userId else { return }
        // Cap the payload so the profile item stays well under DynamoDB's 400KB.
        let capped = lists.prefix(50).map { list -> SwipeList in
            var l = list
            l.posts = Array(l.posts.prefix(100))
            return l
        }
        guard let data = try? JSONEncoder().encode(Array(capped)),
              let arr = try? JSONSerialization.jsonObject(with: data) else { return }
        try? await APIClient.shared.saveMeRaw(userId: userId, profile: ["giftBoards": arr])
    }

    // Local write + debounced server sync (every mutation goes through here).
    private func persist() {
        persistLocalOnly()
        scheduleSync()
    }

    private func persistLocalOnly() {
        if let data = try? JSONEncoder().encode(lists) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
