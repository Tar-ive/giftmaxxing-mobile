import Foundation

// Two-tier browse taxonomy for the Home feed.
//
//   Tier 1 — macro theme ("Occasions", "Cozy Desk", "Coffee Snob"). Swipe or tap
//            between them; each is a different feed query.
//   Tier 2 — micro tags scoped to the active theme ("Pour-over kits", "Under
//            $50"). Tapping one narrows the SAME grid in place; it never pushes
//            a new screen, because the whole point is to keep browsing.
//
// The tags are declared here rather than mined from the catalog on purpose: a
// tag that returns nothing is worse than no tag, and the catalog's own vibe
// labels are store-level junk (measured: 'romantic' = 0 posts, 'golf' = 0).
// These are phrased as retrieval queries and go through the same text→vector
// path the shelves use.
struct FeedTheme: Identifiable, Hashable {
    let id: String
    let title: String
    /// Free-text sent to the feed as `vibes` — what actually selects candidates.
    let query: String
    let tags: [FeedTag]

    // MEASURED: `vibes` matches a CLOSED vocabulary of ~40 tags, counted live
    // across 4,045 posts — aesthetic(1402), curated(1396), minimalist(871),
    // glam(522), makeup(432), classic(360), mens(343), sustainable(322),
    // luxury(225), trendy(217), tech(186), gadget(172), cozy(141),
    // fitness(130), sporty(126), outdoorsy(118), foodie(105), coffee(65)…
    //
    // The first version of this file invented free text ("matcha", "dripper",
    // "kettle"). None of those are tags, so every query scored zero on the
    // taste term and the grid fell back to social proof — which is why the same
    // Gymshark t-shirt appeared under every pill and `vibes=matcha` returned
    // zero matcha items out of 22.
    //
    // Themes now use REAL tags. Sub-tags may use free words too: the server
    // falls back to matching them against product titles and Rekognition image
    // labels when no vibe tag hits.
    static let all: [FeedTheme] = [
        FeedTheme(id: "for-you", title: "For you", query: "", tags: []),

        FeedTheme(
            id: "cozy", title: "Cozy",
            query: "cozy",
            tags: [
                .init(id: "candles", title: "Candles", query: "candle"),
                .init(id: "blankets", title: "Blankets", query: "blanket throw"),
                .init(id: "mugs", title: "Mugs", query: "mug"),
                .init(id: "under-30", title: "Under $30", query: "cozy", maxPrice: 30),
            ]
        ),

        FeedTheme(
            id: "beauty", title: "Beauty",
            query: "makeup glam clean-beauty",
            tags: [
                .init(id: "skincare", title: "Skincare", query: "serum moisturizer skincare"),
                .init(id: "lips", title: "Lips", query: "lipstick gloss"),
                .init(id: "fragrance", title: "Fragrance", query: "perfume fragrance"),
                .init(id: "brushes", title: "Brushes", query: "brush palette"),
                .init(id: "under-25", title: "Under $25", query: "makeup", maxPrice: 25),
            ]
        ),

        FeedTheme(
            id: "tech", title: "Tech",
            query: "tech gadget edc",
            tags: [
                .init(id: "audio", title: "Audio", query: "headphones earbuds speaker"),
                .init(id: "charging", title: "Charging", query: "charger cable power"),
                .init(id: "desk", title: "Desk", query: "keyboard stand desk"),
                .init(id: "carry", title: "Carry", query: "wallet keychain organizer"),
            ]
        ),

        FeedTheme(
            id: "foodie", title: "Foodie",
            query: "foodie coffee",
            tags: [
                .init(id: "coffee", title: "Coffee", query: "coffee espresso"),
                .init(id: "tea", title: "Tea", query: "tea matcha"),
                .init(id: "kitchen", title: "Kitchen", query: "kitchen cookware"),
                .init(id: "sweets", title: "Sweets", query: "chocolate cake dessert"),
            ]
        ),

        FeedTheme(
            id: "minimalist", title: "Minimalist",
            query: "minimalist classic",
            tags: [
                .init(id: "jewelry", title: "Jewelry", query: "jewelry necklace ring"),
                .init(id: "leather", title: "Leather", query: "leather wallet"),
                .init(id: "stationery", title: "Stationery", query: "notebook pen stationery"),
            ]
        ),

        FeedTheme(
            id: "mens", title: "For him",
            query: "mens grooming",
            tags: [
                .init(id: "grooming", title: "Grooming", query: "grooming beard shave"),
                .init(id: "edc", title: "Everyday carry", query: "edc knife multitool"),
                .init(id: "apparel", title: "Apparel", query: "shirt hoodie"),
            ]
        ),

        FeedTheme(
            id: "fitness", title: "Fitness",
            query: "fitness sporty",
            tags: [
                .init(id: "gym", title: "Gym", query: "gym training"),
                .init(id: "bottles", title: "Bottles", query: "bottle flask hydration"),
                .init(id: "shoes", title: "Shoes", query: "shoes sneaker running"),
            ]
        ),

        FeedTheme(
            id: "outdoorsy", title: "Outdoors",
            query: "outdoorsy rugged waterproof",
            tags: [
                .init(id: "camp", title: "Camping", query: "camping tent"),
                .init(id: "trail", title: "Trail", query: "hiking backpack"),
            ]
        ),

        FeedTheme(
            id: "sustainable", title: "Sustainable",
            query: "sustainable natural handmade",
            tags: [
                .init(id: "handmade", title: "Handmade", query: "handmade"),
                .init(id: "refill", title: "Refillable", query: "refill reusable"),
            ]
        ),

        FeedTheme(
            id: "luxury", title: "Luxury",
            query: "luxury premium",
            tags: [
                .init(id: "jewelry", title: "Jewelry", query: "jewelry"),
                .init(id: "fragrance", title: "Fragrance", query: "perfume fragrance"),
                .init(id: "over-100", title: "Splurge", query: "luxury"),
            ]
        ),
    ]
}

struct FeedTag: Identifiable, Hashable {
    let id: String
    let title: String
    let query: String
    /// Client-side price ceiling for "Under $N" tags. The feed endpoint has no
    /// price filter, so this is enforced on the returned page.
    var maxPrice: Double?
}
