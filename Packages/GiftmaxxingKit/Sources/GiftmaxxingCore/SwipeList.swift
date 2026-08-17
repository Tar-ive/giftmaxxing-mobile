import Foundation

// A Gift Board — "saw it, thought of you", per PERSON. (UI name: Gift Board;
// the type keeps its original name to avoid churning every call site.) Like
// Instagram's bookmark collections: you keep several ("Sarah's birthday",
// "Dad — retirement"), add finds from the feed or search into whichever fits,
// annotate WHY each fits, write a gift letter, then send it as a swipe deck.
// The recipient swipes yes/no on exactly those items — direct buy/don't-buy
// signals for the giver.
public struct SwipeList: Identifiable, Codable, Hashable {
    public var id: String = UUID().uuidString
    public var name: String
    public var recipientName: String?
    public var occasion: String?
    // Relationship type — the primary edge of the gift graph (a gift for a
    // spouse is not a gift for a boss); powers GiftGraphRanker's traversal.
    public var relationship: String?
    public var createdAt: Date = Date()
    public var posts: [Post] = []
    // Per-item "why this fits them" notes (postId → note) — the thoughtful
    // half of the board, and the one-line why on Signature Gifts.
    public var notes: [String: String]?
    // The digital gift letter — words that outlast the wrapping; it rides
    // along with the board's share message.
    public var letter: String?

    // Private purchase checklist — the postIds the giver has already bought.
    // Local to the giver: it never rides along in the shared swipe deck (that
    // stays a clean yes/no for the recipient), only syncs across the giver's
    // own devices via the giftBoards profile like everything else here.
    public var boughtPostIds: Set<String>?

    // Sharing state — set once the board has been sent as a swipe deck. The
    // link goes stale the moment the board's CONTENTS change, not just its
    // count, so the exact item set it was built for rides along.
    public var challengeId: String?
    public var shareURLString: String?
    public var sharedContentsKey: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        recipientName: String? = nil,
        occasion: String? = nil,
        relationship: String? = nil,
        createdAt: Date = Date(),
        posts: [Post] = [],
        notes: [String: String]? = nil,
        letter: String? = nil,
        boughtPostIds: Set<String>? = nil,
        challengeId: String? = nil,
        shareURLString: String? = nil,
        sharedContentsKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.recipientName = recipientName
        self.occasion = occasion
        self.relationship = relationship
        self.createdAt = createdAt
        self.posts = posts
        self.notes = notes
        self.letter = letter
        self.boughtPostIds = boughtPostIds
        self.challengeId = challengeId
        self.shareURLString = shareURLString
        self.sharedContentsKey = sharedContentsKey
    }


    public var contentsKey: String { posts.map(\.id).joined(separator: "|") }
    public var shareURL: URL? {
        guard let shareURLString, sharedContentsKey == contentsKey else { return nil }
        return URL(string: shareURLString)
    }

    public func note(for postId: String) -> String? {
        guard let note = notes?[postId], !note.isEmpty else { return nil }
        return note
    }

    public func isBought(_ postId: String) -> Bool { boughtPostIds?.contains(postId) ?? false }

    // How many of the board's current items are checked off. Only counts items
    // still on the board, so removing a bought item doesn't leave a stale tally.
    public var boughtCount: Int {
        guard let boughtPostIds else { return 0 }
        return posts.reduce(0) { $0 + (boughtPostIds.contains($1.id) ? 1 : 0) }
    }
}
