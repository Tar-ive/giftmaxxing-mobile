import Foundation
import GiftmaxxingCore

// Per-account cart, local-first with server sync.
//
// Deliberately the same shape as SwipeListStore: UserDefaults is the fast path,
// and every mutation debounce-pushes into the EXISTING `/me` profile under a
// new `cart` field. PUT /me merges patches server-side (handler.mjs), so this
// needs no backend deploy and survives sign-out, reinstall and new devices —
// the same guarantee Gift Boards already have.
@MainActor
final class CartStore: ObservableObject {
    static let shared = CartStore()

    private static let storageKey = "giftmaxxing_cart_sections"
    // The cart shares ONE DynamoDB item with Gift Boards (both live on the
    // USERS row via /me), and that item is hard-capped at 400KB. Boards already
    // claim 50 × 100 posts, so the cart stays deliberately small — and
    // `pushToServer` additionally strips each Post's comments, which are pure
    // dead weight here and are the single biggest contributor to a Post's
    // encoded size. Blowing the limit fails the write silently and takes
    // BOTH stores' sync down with it.
    private static let maxSections = 12
    private static let maxItemsPerSection = 25

    @Published private(set) var sections: [CartSection] = []

    private var userId: String?
    private var syncTask: Task<Void, Never>?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([CartSection].self, from: data) {
            sections = saved
        }
    }

    // MARK: - Derived

    /// Badge count = things still to buy. Bought items shouldn't nag.
    var pendingCount: Int {
        sections.reduce(0) { $0 + $1.items.filter { !$0.bought }.count }
    }

    var total: Double { sections.reduce(0) { $0 + $1.subtotal } }

    var isEmpty: Bool { sections.allSatisfy(\.items.isEmpty) }

    func contains(_ post: Post) -> Bool {
        sections.contains { $0.contains(post.id) }
    }

    func section(id: String) -> CartSection? {
        sections.first { $0.id == id }
    }

    /// Sections ordered the way a giver thinks: real people before the
    /// unassigned bucket, then by how recently they were touched.
    var sortedSections: [CartSection] {
        sections.sorted { a, b in
            if a.isUnassigned != b.isUnassigned { return !a.isUnassigned }
            return a.createdAt > b.createdAt
        }
    }

    // MARK: - Mutations

    @discardableResult
    func sectionFor(
        recipientName: String?,
        relationship: String? = nil,
        occasion: String? = nil,
        boardId: String? = nil
    ) -> CartSection {
        let name = (recipientName?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? CartSection.unassignedName

        // Match case-insensitively: Maxi says "mom", the board says "Mom".
        if let index = sections.firstIndex(where: {
            $0.recipientName.compare(name, options: .caseInsensitive) == .orderedSame
        }) {
            // Fill in anything we've since learned about this person.
            if sections[index].relationship == nil { sections[index].relationship = relationship }
            if sections[index].occasion == nil { sections[index].occasion = occasion }
            if sections[index].boardId == nil { sections[index].boardId = boardId }
            persist()
            return sections[index]
        }

        let created = CartSection(
            recipientName: name,
            relationship: relationship,
            occasion: occasion,
            boardId: boardId
        )
        sections.insert(created, at: 0)
        persist()
        return created
    }

    /// Add a find to someone's pile. Adding something already there bumps the
    /// quantity rather than duplicating the row.
    func add(
        _ post: Post,
        for recipientName: String?,
        relationship: String? = nil,
        occasion: String? = nil,
        boardId: String? = nil,
        source: String? = nil
    ) {
        let target = sectionFor(
            recipientName: recipientName,
            relationship: relationship,
            occasion: occasion,
            boardId: boardId
        )
        guard let index = sections.firstIndex(where: { $0.id == target.id }) else { return }

        if let existing = sections[index].items.firstIndex(where: { $0.id == post.id }) {
            sections[index].items[existing].qty += 1
        } else {
            sections[index].items.insert(
                CartItem(id: post.id, post: post, source: source),
                at: 0
            )
            sections[index].items = Array(sections[index].items.prefix(Self.maxItemsPerSection))
        }
        persist()
    }

    func remove(postId: String, from sectionId: String) {
        guard let index = sections.firstIndex(where: { $0.id == sectionId }) else { return }
        sections[index].items.removeAll { $0.id == postId }
        persist()
    }

    func setQuantity(_ qty: Int, for postId: String, in sectionId: String) {
        guard let s = sections.firstIndex(where: { $0.id == sectionId }),
              let i = sections[s].items.firstIndex(where: { $0.id == postId }) else { return }
        if qty <= 0 {
            sections[s].items.remove(at: i)
        } else {
            sections[s].items[i].qty = min(qty, 99)
        }
        persist()
    }

    func toggleBought(postId: String, in sectionId: String) {
        guard let s = sections.firstIndex(where: { $0.id == sectionId }),
              let i = sections[s].items.firstIndex(where: { $0.id == postId }) else { return }
        sections[s].items[i].bought.toggle()
        persist()
    }

    /// Re-home an item — the fix for anything that landed in the unassigned
    /// bucket, and for "actually this is better for Dad".
    func move(postId: String, from sectionId: String, to targetName: String) {
        guard let s = sections.firstIndex(where: { $0.id == sectionId }),
              let i = sections[s].items.firstIndex(where: { $0.id == postId }) else { return }
        let item = sections[s].items.remove(at: i)
        let target = sectionFor(recipientName: targetName)
        guard let t = sections.firstIndex(where: { $0.id == target.id }) else { return }
        if !sections[t].items.contains(where: { $0.id == item.id }) {
            sections[t].items.insert(item, at: 0)
        }
        persist()
    }

    func updateSection(
        id: String,
        recipientName: String? = nil,
        relationship: String? = nil,
        occasion: String? = nil
    ) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        if let recipientName, !recipientName.trimmingCharacters(in: .whitespaces).isEmpty {
            sections[index].recipientName = recipientName
        }
        if let relationship { sections[index].relationship = relationship }
        if let occasion { sections[index].occasion = occasion }
        persist()
    }

    func deleteSection(id: String) {
        sections.removeAll { $0.id == id }
        persist()
    }

    /// Commit a whole Gift Board (or an idea pack) at once.
    func addAll(
        _ posts: [Post],
        for recipientName: String?,
        relationship: String? = nil,
        occasion: String? = nil,
        boardId: String? = nil,
        source: String? = nil
    ) {
        for post in posts {
            add(
                post,
                for: recipientName,
                relationship: relationship,
                occasion: occasion,
                boardId: boardId,
                source: source
            )
        }
    }

    // MARK: - Account boundary

    func clear() {
        sections = []
        syncTask?.cancel()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Server sync (per account, via the existing /me profile)

    func configure(userId: String?) {
        self.userId = userId
        guard userId != nil else { return }
        Task { await hydrateFromServer() }
    }

    private func hydrateFromServer() async {
        guard let userId else { return }
        let profile = try? await APIClient.shared.fetchMe(userId: userId)
        let remote = profile?.cart ?? []
        if remote.isEmpty {
            if !isEmpty { scheduleSync() } // back up what this device has
            return
        }
        // Server is the cross-device truth; keep local-only sections (offline
        // or guest-then-claimed) and push them up.
        let remoteIds = Set(remote.map(\.id))
        var merged = remote
        for local in sections where !remoteIds.contains(local.id) {
            merged.insert(local, at: 0)
        }
        sections = merged
        persistLocalOnly()
        if merged.count != remote.count { scheduleSync() }
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
        let capped = sections.prefix(Self.maxSections).map { section -> CartSection in
            var s = section
            s.items = Array(s.items.prefix(Self.maxItemsPerSection)).map { item in
                var i = item
                // Comments are the heaviest part of a Post and mean nothing in
                // a cart — drop them before they eat the shared item budget.
                i.post.comments = []
                return i
            }
            return s
        }
        guard let data = try? JSONEncoder().encode(Array(capped)),
              let arr = try? JSONSerialization.jsonObject(with: data) else { return }
        #if DEBUG
        // The 400KB ceiling is shared with Gift Boards and fails silently.
        // Surface the trend before it becomes a support ticket.
        if data.count > 120_000 {
            print("⚠️ CartStore payload \(data.count / 1024)KB — shared /me item is filling up")
        }
        #endif
        try? await APIClient.shared.saveMeRaw(userId: userId, profile: ["cart": arr])
    }

    private func persist() {
        persistLocalOnly()
        scheduleSync()
    }

    private func persistLocalOnly() {
        if let data = try? JSONEncoder().encode(sections) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
