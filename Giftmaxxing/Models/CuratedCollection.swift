import Foundation

// A curated gift gallery — "Anniversary Gifts Under $50", "For the Golf Lover".
// The immersive first-launch surface: themed shelves of intentional gifts the
// user can browse without any setup. Today each shelf pulls REAL catalog
// products filtered by its theme (a light "curation by query"); the editorial /
// power-user curation layer slots in behind the same model later.
struct CuratedCollection: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let emoji: String
    /// Real vector art for the card (AppIcons) — emoji stays for copy only.
    var symbol: String { AppIcons.collection(id) }
    let grad: GradientStyle
    // Theme → feed query. vibes/category seed candidate generation; occasion +
    // recipient bias it; maxPrice is applied client-side so the "Under $X"
    // promise always holds even if the server ignores the budget hint.
    var vibes: [String] = []
    var category: String? = nil
    var occasion: String? = nil
    var recipient: String? = nil
    var maxPrice: Double? = nil

    // Bundled filler shelves. Ordered so occasions + interests + price bands are
    // all represented on the first screen.
    static let all: [CuratedCollection] = [
        CuratedCollection(
            id: "anniversary-under-50", title: "Anniversary Gifts Under $50",
            subtitle: "Thoughtful, not pricey", emoji: "💝", grad: .rose,
            vibes: ["romantic", "classic", "luxury"], occasion: "anniversary", maxPrice: 50
        ),
        CuratedCollection(
            id: "golf-lover", title: "For the Golf Lover",
            subtitle: "Tee-time treats", emoji: "⛳️", grad: .sage,
            vibes: ["golf", "sporty", "outdoorsy"], category: "fitness"
        ),
        CuratedCollection(
            id: "coffee-obsessed", title: "For the Coffee Obsessed",
            subtitle: "Beans, brewers & mugs", emoji: "☕️", grad: .peach,
            vibes: ["coffee", "foodie", "cozy"], category: "food"
        ),
        CuratedCollection(
            id: "tech-wishlist", title: "The Tech Lover's Wishlist",
            subtitle: "Gadgets they'll actually use", emoji: "🎧", grad: .sky,
            vibes: ["tech", "gadget", "minimalist"], category: "tech"
        ),
        CuratedCollection(
            id: "beauty-glow", title: "Beauty & Glow",
            subtitle: "Makeup & self-care picks", emoji: "💄", grad: .lilac,
            vibes: ["makeup", "glam", "selfcare"], category: "beauty"
        ),
        CuratedCollection(
            id: "for-him-essentials", title: "For Him: The Essentials",
            subtitle: "Everyday upgrades", emoji: "🧢", grad: .butter,
            vibes: ["mens", "classic", "everyday"], recipient: "men"
        ),
        CuratedCollection(
            id: "cozy-nights", title: "Cozy Nights In",
            subtitle: "Soft, warm, unwind", emoji: "🕯️", grad: .peach,
            vibes: ["cozy", "minimalist", "wellness"]
        ),
        CuratedCollection(
            id: "under-25", title: "Little Luxuries Under $25",
            subtitle: "Small gifts, big smiles", emoji: "🎀", grad: .rose,
            vibes: ["fun", "affordable"], maxPrice: 25
        ),
        CuratedCollection(
            id: "birthday-showstoppers", title: "Birthday Showstoppers",
            subtitle: "Make the day", emoji: "🎂", grad: .coral,
            vibes: ["fun", "trendy", "glam"], occasion: "birthday"
        ),
        CuratedCollection(
            id: "sustainable", title: "Sustainable & Thoughtful",
            subtitle: "Kind to the planet", emoji: "🌿", grad: .sage,
            vibes: ["sustainable", "minimalist", "outdoorsy"]
        ),
        CuratedCollection(
            id: "fitness-fanatic", title: "For the Fitness Fanatic",
            subtitle: "Move-more motivation", emoji: "🏋️", grad: .sky,
            vibes: ["fitness", "sporty", "wellness"], category: "fitness"
        ),
        CuratedCollection(
            id: "minimalist", title: "Minimalist Picks",
            subtitle: "Clean, considered design", emoji: "◻️", grad: .lilac,
            vibes: ["minimalist", "premium", "classic"]
        ),
    ]
}
