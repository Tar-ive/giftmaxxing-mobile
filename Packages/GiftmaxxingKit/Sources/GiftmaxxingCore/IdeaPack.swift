import Foundation

// One shape for everything on the Ideas surface.
//
// Two very different things used to sit in two separate Home rails: curated
// galleries ("Cozy Nights In" — a themed shelf, server-curated by semantic
// kNN) and Reddit-mined bundles ("candle + blanket" — things people suggest
// together). To a user they're the same object: a pack of ideas you can browse,
// pick from, or take wholesale. Normalizing them here is what lets one rail,
// one grid and one detail screen serve both — and what makes "add the whole
// pack to someone's cart" a single code path.
//
// A gallery is a one-section pack. A bundle is a pack with one section per
// slot, where each slot offers alternatives for the same idea.
public struct IdeaPack: Identifiable, Hashable {
    public enum Kind: String, Hashable {
        case gallery   // themed shelf — pick what you like
        case bundle    // things that go together — one pick per slot
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let subtitle: String
    /// Bundles carry the reason they exist ("Often suggested together").
    public let why: String?
    public let symbol: String
    public let grad: GradientStyle
    public var coverImage: String?
    public var sections: [IdeaSection]

    public init(
        id: String,
        kind: Kind,
        title: String,
        subtitle: String,
        why: String?,
        symbol: String,
        grad: GradientStyle,
        coverImage: String? = nil,
        sections: [IdeaSection]
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.why = why
        self.symbol = symbol
        self.grad = grad
        self.coverImage = coverImage
        self.sections = sections
    }

    public var allItems: [Post] { sections.flatMap(\.items) }
    public var itemCount: Int { allItems.count }

    /// A bundle's point is one thing per slot; a gallery has no such notion,
    /// so "add everything" would be nonsense there.
    public var supportsWholePackAdd: Bool { kind == .bundle }

    /// One representative per slot — what "add the whole pack" commits.
    public var representativeItems: [Post] {
        kind == .bundle ? sections.compactMap(\.items.first) : allItems
    }
}

public struct IdeaSection: Identifiable, Hashable {
    public let id: String
    /// Bundles label each slot ("Cozy blanket"); galleries have none.
    public let label: String?
    public let emoji: String?
    public var items: [Post]

    public init(id: String, label: String?, emoji: String?, items: [Post]) {
        self.id = id
        self.label = label
        self.emoji = emoji
        self.items = items
    }
}

extension IdeaPack {
    public static func from(_ collection: CuratedCollection, items: [Post]) -> IdeaPack {
        IdeaPack(
            id: "gallery:\(collection.id)",
            kind: .gallery,
            title: collection.title,
            subtitle: collection.subtitle,
            why: nil,
            symbol: collection.symbol,
            grad: collection.grad,
            coverImage: items.first?.product.image,
            sections: [IdeaSection(id: collection.id, label: nil, emoji: nil, items: items)]
        )
    }
}

// The server's bundle key is a raw recipient slug ("mom", "age-teen-13-17").
// Turning it into something a person would say is client-side so no deploy is
// needed when a new band ships.
public enum RecipientLabel {
    private static let known: [String: String] = [
        "mom": "For Mom", "dad": "For Dad", "wife": "For your wife",
        "husband": "For your husband", "girlfriend": "For your girlfriend",
        "boyfriend": "For your boyfriend", "partner": "For your partner",
        "couple": "For a couple", "sister": "For your sister",
        "brother": "For your brother", "daughter": "For your daughter",
        "son": "For your son", "parents": "For your parents",
        "grandma": "For Grandma", "grandpa": "For Grandpa",
        "kids": "For kids", "teen": "For teens", "friend": "For a friend",
        "coworker": "For a coworker", "teacher": "For a teacher",
        "men": "For him", "women": "For her", "self": "For yourself",
        "anyone": "For anyone",
    ]

    // Age packs are keyed "age-teen-13-17" -> "Ages 13–17". Parsing the range
    // off the slug keeps new bands working without a client update.
    public static func display(_ recipient: String) -> String {
        let key = recipient.lowercased()
        if let known = known[key] { return known }
        guard key.hasPrefix("age-") else { return key.capitalized }

        let parts = key.dropFirst(4).split(separator: "-")
        let numbers = parts.compactMap { Int($0) }
        if numbers.count >= 2 { return "Ages \(numbers[0])–\(numbers[1])" }
        if let first = numbers.first, key.hasSuffix("plus") { return "Ages \(first)+" }
        if let first = numbers.first { return "Ages \(first)+" }
        return parts.joined(separator: " ").capitalized
    }
}
