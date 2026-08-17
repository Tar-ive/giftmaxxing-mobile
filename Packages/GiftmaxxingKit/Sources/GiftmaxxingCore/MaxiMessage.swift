import Foundation

// Codable so the transcript survives dismissing the sheet and relaunching the
// app (MaxiConversationStore). A concierge that forgets what you told it two
// minutes ago is not a concierge.
public struct MaxiMessage: Identifiable, Codable {
    public let id: String
    public var role: MessageRole
    public var text: String
    public var products: [MaxiProduct]
    public var steps: [MaxiStep]
    public var chips: [String]
    /// Was this set of picks any good? nil = not rated yet. Cheap, one-tap
    /// feedback beats asking a question — and it is a LABEL, which is the thing
    /// the ranker is starved of.
    public var rating: Int?
    public var timestamp: Date

    public init(
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

public enum MessageRole: String, Codable {
    case user
    case assistant
}

public struct MaxiProduct: Identifiable, Codable {
    public let postId: String
    public var title: String
    public var price: Double?
    public var brand: String?
    public var image: String?
    public var category: String?
    /// Catalog-authored description of what is visible in the product photo.
    /// Maxi receives this automatically; no separate image upload is required.
    public var visualContext: String? = nil

    public init(
        postId: String,
        title: String,
        price: Double? = nil,
        brand: String? = nil,
        image: String? = nil,
        category: String? = nil,
        visualContext: String? = nil
    ) {
        self.postId = postId
        self.title = title
        self.price = price
        self.brand = brand
        self.image = image
        self.category = category
        self.visualContext = visualContext
    }


    public var id: String { postId }
}

extension Post {
    /// A product Maxi surfaced, rendered as a Post so it can enter the cart,
    /// a Gift Board, or the detail sheet like anything else. MaxiProduct has no
    /// product URL — `Affiliate.productUrl(for:)` falls through to a tagged
    /// retailer search, which is its documented behaviour for link-less items.
    public init(maxiProduct product: MaxiProduct) {
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
            caption: product.visualContext ?? "",
            likes: 0,
            reason: "Maxi picked this",
            category: product.category
        )
    }
}

public struct MaxiStep: Identifiable, Codable {
    public var tool: String
    public var label: String
    public var detail: String?

    public var id: String { "\(tool)-\(label)" }
}

// What Maxi thinks the current job is: who it's for, the occasion, the budget,
// what they're into. Surfaced as a chip above the conversation so the user can
// see — and correct — the assumptions the picks are being made from.
public struct GiftBrief: Codable, Hashable {
    public var recipientName: String?
    public var relationship: String?
    public var occasion: String?
    public var date: String?
    public var budgetMin: Double?
    public var budgetMax: Double?
    public var interests: [String]?
    public var avoid: [String]?
    public var alreadyGiven: [String]?

    /// "Mom · birthday · under $75" — only the parts that are actually known.
    public var summary: String {
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

    public var isEmpty: Bool { summary.isEmpty }
}

// One stored turn from GET /maxi/history — a user message and Maxi's reply,
// with the product cards it showed, so a restored conversation looks the same
// as the live one rather than a wall of text.
public struct MaxiHistoryTurn: Codable {
    public var at: Double?
    public var user: String?
    public var say: String?
    public var pins: [MaxiProduct]?
}

public struct MaxiHistoryResponse: Codable {
    public var items: [MaxiHistoryTurn]?
}

public struct MaxiAgentReply: Codable {
    public var say: String
    public var pins: [MaxiProduct]
    public var actions: [MaxiAction]
    public var steps: [MaxiStep]
    public var source: String
    /// Absent on older deployments — the chip just doesn't render.
    public var brief: GiftBrief?

    // The agent tells the client what to do rather than doing it server-side:
    // the cart and Gift Boards are local-first stores synced through /me, so a
    // server write would race their debounced push. `recipient`/`occasion` are
    // optional so an older deployment (which sends neither) still works.
    public struct MaxiAction: Codable {
        public var type: String
        public var postIds: [String]?
        public var recipient: String?
        public var occasion: String?
    }
}
