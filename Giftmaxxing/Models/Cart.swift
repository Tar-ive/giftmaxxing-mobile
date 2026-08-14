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
struct CartSection: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var recipientName: String
    /// Same vocabulary as SwipeList.relationship — feeds GiftGraphRanker and
    /// tunes packaging tone (a boss's wrap is not a partner's wrap).
    var relationship: String?
    var occasion: String?
    /// The Gift Board these items were committed from, when there was one.
    var boardId: String?
    var createdAt: Date = Date()
    var items: [CartItem] = []

    /// Everything still to buy — bought items stay for the record but drop out
    /// of the total so the number means "what this still costs me".
    var subtotal: Double {
        items.filter { !$0.bought }.reduce(0) { $0 + $1.lineTotal }
    }

    var boughtCount: Int { items.filter(\.bought).count }
    var isComplete: Bool { !items.isEmpty && boughtCount == items.count }

    func contains(_ postId: String) -> Bool {
        items.contains { $0.id == postId }
    }
}

struct CartItem: Identifiable, Codable, Hashable {
    /// == post.id, so membership checks are cheap and de-dup is free.
    var id: String
    var post: Post
    var qty: Int = 1
    /// Parity with SwipeList.boughtPostIds — the private purchase checklist.
    var bought: Bool = false
    var addedAt: Date = Date()
    /// Where this came from: "feed", "maxi", "idea-pack", "board", "search".
    var source: String?

    var lineTotal: Double { post.product.price * Double(max(1, qty)) }
}

// The unassigned bucket: things you liked enough to commit to before deciding
// who they're for. Named rather than optional so it renders like any other
// section and can be re-homed with one tap.
extension CartSection {
    static let unassignedName = "Not assigned yet"
    var isUnassigned: Bool { recipientName == Self.unassignedName }
}

struct CartPreparationProgress: Equatable {
    let preparedPeople: Int
    let totalPeople: Int

    init(sections: [CartSection]) {
        let people = sections.filter { !$0.isUnassigned && !$0.items.isEmpty }
        preparedPeople = people.filter(\.isComplete).count
        totalPeople = people.count
    }

    var fraction: Double {
        guard totalPeople > 0 else { return 0 }
        return Double(preparedPeople) / Double(totalPeople)
    }
}
