import Foundation

// Codable so the transcript survives dismissing the sheet and relaunching the
// app (MaxiConversationStore). A concierge that forgets what you told it two
// minutes ago is not a concierge.
struct MaxiMessage: Identifiable, Codable {
    let id: String
    var role: MessageRole
    var text: String
    var products: [MaxiProduct]
    var steps: [MaxiStep]
    var chips: [String]
    /// Was this set of picks any good? nil = not rated yet. Cheap, one-tap
    /// feedback beats asking a question — and it is a LABEL, which is the thing
    /// the ranker is starved of.
    var rating: Int?
    var timestamp: Date

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        text: String,
        products: [MaxiProduct] = [],
        steps: [MaxiStep] = [],
        chips: [String] = [],
        rating: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.products = products
        self.steps = steps
        self.chips = chips
        self.rating = rating
        self.timestamp = timestamp
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
}

struct MaxiProduct: Identifiable, Codable {
    let postId: String
    var title: String
    var price: Double?
    var brand: String?
    var image: String?
    var category: String?

    var id: String { postId }
}

extension Post {
    /// A product Maxi surfaced, rendered as a Post so it can enter the cart,
    /// a Gift Board, or the detail sheet like anything else. MaxiProduct has no
    /// product URL — `Affiliate.productUrl(for:)` falls through to a tagged
    /// retailer search, which is its documented behaviour for link-less items.
    init(maxiProduct product: MaxiProduct) {
        self.init(
            id: product.postId,
            user: product.brand ?? "giftmaxxing",
            time: "",
            product: Product(
                id: product.postId,
                name: product.title,
                brand: product.brand ?? "",
                price: product.price ?? 0,
                grad: .coral,
                emoji: "🎁",
                image: product.image
            ),
            caption: "",
            likes: 0,
            reason: "Maxi picked this",
            category: product.category
        )
    }
}

struct MaxiStep: Identifiable, Codable {
    var tool: String
    var label: String
    var detail: String?

    var id: String { "\(tool)-\(label)" }
}

// What Maxi thinks the current job is: who it's for, the occasion, the budget,
// what they're into. Surfaced as a chip above the conversation so the user can
// see — and correct — the assumptions the picks are being made from.
struct GiftBrief: Codable, Hashable {
    var recipientName: String?
    var relationship: String?
    var occasion: String?
    var date: String?
    var budgetMin: Double?
    var budgetMax: Double?
    var interests: [String]?
    var avoid: [String]?
    var alreadyGiven: [String]?

    /// "Mom · birthday · under $75" — only the parts that are actually known.
    var summary: String {
        var parts: [String] = []
        if let name = recipientName, !name.isEmpty { parts.append(name) }
        if let occasion, !occasion.isEmpty { parts.append(occasion) }
        if let max = budgetMax, max > 0 {
            parts.append("under $\(Int(max))")
        } else if let min = budgetMin, min > 0 {
            parts.append("from $\(Int(min))")
        }
        if let interests, let first = interests.first, parts.count < 3 { parts.append(first) }
        return parts.joined(separator: " · ")
    }

    var isEmpty: Bool { summary.isEmpty }
}

// One stored turn from GET /maxi/history — a user message and Maxi's reply,
// with the product cards it showed, so a restored conversation looks the same
// as the live one rather than a wall of text.
struct MaxiHistoryTurn: Codable {
    var at: Double?
    var user: String?
    var say: String?
    var pins: [MaxiProduct]?
}

struct MaxiHistoryResponse: Codable {
    var items: [MaxiHistoryTurn]?
}

struct MaxiAgentReply: Codable {
    var say: String
    var pins: [MaxiProduct]
    var actions: [MaxiAction]
    var steps: [MaxiStep]
    var source: String
    /// Absent on older deployments — the chip just doesn't render.
    var brief: GiftBrief?

    // The agent tells the client what to do rather than doing it server-side:
    // the cart and Gift Boards are local-first stores synced through /me, so a
    // server write would race their debounced push. `recipient`/`occasion` are
    // optional so an older deployment (which sends neither) still works.
    struct MaxiAction: Codable {
        var type: String
        var postIds: [String]?
        var recipient: String?
        var occasion: String?
    }
}
