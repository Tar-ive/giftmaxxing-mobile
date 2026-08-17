import Foundation

// The cart is organised by PERSON, not as one flat list.
//
// Gifting isn't shopping: you're never buying "5 things", you're buying two
// things for Mom and three for your partner, on different dates and different
// budgets. A flat cart forces you to hold that split in your head. Sections
// make the split the structure, which is also what lets packaging suggestions
// (one wrap plan per recipient's pile) and per-person budgets work at all.
//
// Relationship to Gift Boards (SwipeList): a board is *ideas for a person* —
// open-ended, annotated, shareable as a swipe deck. A cart section is *what
// I'm actually buying for them now* — priced, finite, checkout-able. Items
// flow board → cart when you commit, and `boardId` keeps the link so the
// board's letter and notes can ride along to packaging.
public struct CartSection: Identifiable, Codable, Hashable {
    public var id: String = UUID().uuidString
    public var recipientName: String
    /// Same vocabulary as SwipeList.relationship — feeds GiftGraphRanker and
    /// tunes packaging tone (a boss's wrap is not a partner's wrap).
    public var relationship: String?
    public var occasion: String?
    /// The Gift Board these items were committed from, when there was one.
    public var boardId: String?
    public var createdAt: Date = Date()
    public var items: [CartItem] = []

    public init(
        id: String = UUID().uuidString,
        recipientName: String,
        relationship: String? = nil,
        occasion: String? = nil,
        boardId: String? = nil,
        createdAt: Date = Date(),
        items: [CartItem] = []
    ) {
        self.id = id
        self.recipientName = recipientName
        self.relationship = relationship
        self.occasion = occasion
        self.boardId = boardId
        self.createdAt = createdAt
        self.items = items
    }


    /// Everything still to buy — bought items stay for the record but drop out
    /// of the total so the number means "what this still costs me".
    public var subtotal: Double {
        items.filter { !$0.bought }.reduce(0) { $0 + $1.lineTotal }
    }

    public var boughtCount: Int { items.filter(\.bought).count }
    public var isComplete: Bool { !items.isEmpty && boughtCount == items.count }

    public func contains(_ postId: String) -> Bool {
        items.contains { $0.id == postId }
    }
}

public struct CartItem: Identifiable, Codable, Hashable {
    /// == post.id, so membership checks are cheap and de-dup is free.
    public var id: String
    public var post: Post
    public var qty: Int = 1
    /// Parity with SwipeList.boughtPostIds — the private purchase checklist.
    public var bought: Bool = false
    public var addedAt: Date = Date()
    /// Where this came from: "feed", "maxi", "idea-pack", "board", "search".
    public var source: String?

    public init(
        id: String,
        post: Post,
        qty: Int = 1,
        bought: Bool = false,
        addedAt: Date = Date(),
        source: String? = nil
    ) {
        self.id = id
        self.post = post
        self.qty = qty
        self.bought = bought
        self.addedAt = addedAt
        self.source = source
    }


    public var lineTotal: Double { post.product.price * Double(max(1, qty)) }
}

// The unassigned bucket: things you liked enough to commit to before deciding
// who they're for. Named rather than optional so it renders like any other
// section and can be re-homed with one tap.
extension CartSection {
    public static let unassignedName = "Not assigned yet"
    public var isUnassigned: Bool { recipientName == Self.unassignedName }
}

public struct CartPreparationProgress: Equatable {
    public let preparedPeople: Int
    public let totalPeople: Int

    public init(sections: [CartSection]) {
        let people = sections.filter { !$0.isUnassigned && !$0.items.isEmpty }
        preparedPeople = people.filter(\.isComplete).count
        totalPeople = people.count
    }

    public var fraction: Double {
        guard totalPeople > 0 else { return 0 }
        return Double(preparedPeople) / Double(totalPeople)
    }
}
