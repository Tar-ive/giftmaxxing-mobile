import Foundation

// Text-driven facet extraction for arbitrary catalog items. The web app
// hand-tags its demo catalog (web/lib/recommend.ts PRODUCT_META); the live
// Pinterest/Reddit catalog is open-ended, so on device we derive "vibes" and a
// coarse category from the item's title/brand/caption with a keyword map.
// Cheap (runs once per item, memoized by the ranker) and fully offline.

enum TasteSignals {
    // Superset of the web taxonomy (cozy…warm) plus tags that show up in the
    // live pin catalog. Keyword patterns are case-insensitive regexes.
    static let vibeKeywords: [(vibe: String, pattern: String)] = [
        ("cozy", "\\b(cozy|blanket|throw|fuzzy|knit|sweater|fleece|plush|slipper|hygge)\\b"),
        ("tech", "\\b(tech|gadget|smart|wireless|bluetooth|charger|usb|led|electronic|keyboard|drone)\\b"),
        ("kitchen", "\\b(kitchen|mug|coffee|tea|matcha|baking|cook|chef|spice|barista|espresso|cocktail kit)\\b"),
        ("home", "\\b(home|decor|candle|vase|pillow|lamp|shelf|planter|frame|tray|rug)\\b"),
        ("wellness", "\\b(wellness|spa|bath|self[- ]care|aromatherapy|essential oil|massage|meditation|skincare)\\b"),
        ("beauty", "\\b(beauty|makeup|lipstick|perfume|fragrance|serum|palette|nail|hair)\\b"),
        ("luxe", "\\b(luxe|luxury|gold|silk|cashmere|premium|designer|marble|velvet)\\b"),
        ("romantic", "\\b(romantic|love|heart|anniversary|couple|valentine)\\b"),
        ("minimal", "\\b(minimal|simple|clean|modern|sleek|scandinavian)\\b"),
        ("stationery", "\\b(stationery|journal|notebook|planner|pen|sticker|washi|stamp)\\b"),
        ("retro", "\\b(retro|vintage|classic|antique|nostalgi|90s|80s|y2k)\\b"),
        ("music", "\\b(music|vinyl|record|speaker|headphone|earbud|guitar|concert)\\b"),
        ("film", "\\b(film|camera|polaroid|instax|photo|darkroom|lens)\\b"),
        ("calm", "\\b(calm|zen|relax|soothing|lavender|sleep|weighted)\\b"),
        ("warm", "\\b(warm|amber|glow|fireplace|toasty)\\b"),
        ("outdoors", "\\b(outdoor|camping|hik(e|ing)|garden|picnic|adventure|trail|beach)\\b"),
        ("jewelry", "\\b(jewelry|necklace|bracelet|ring|earring|pendant|charm)\\b"),
        ("pets", "\\b(pet|dog|cat|puppy|kitten|paw)\\b"),
        ("games", "\\b(game|puzzle|lego|board game|chess|trivia|nintendo)\\b"),
        ("books", "\\b(book|novel|reading|bookmark|literary|bookish)\\b"),
        ("travel", "\\b(travel|passport|luggage|weekender|map|wanderlust)\\b"),
        ("art", "\\b(art|print|painting|sketch|illustration|poster|craft)\\b"),
        ("fitness", "\\b(fitness|yoga|gym|workout|running|athletic)\\b"),
        ("plants", "\\b(plant|succulent|terrarium|botanical|flower|bouquet)\\b"),
    ]

    // vibe -> coarse category used for feed diversity spacing.
    private static let vibeCategory: [String: String] = [
        "kitchen": "kitchen", "beauty": "beauty", "jewelry": "jewelry", "tech": "tech",
        "music": "music", "film": "photography", "stationery": "stationery", "games": "games",
        "books": "books", "travel": "travel", "art": "art", "fitness": "fitness",
        "plants": "plants", "pets": "pets", "outdoors": "outdoors", "wellness": "wellness",
        "home": "home", "cozy": "home",
    ]

    struct ItemSignals {
        let vibes: [String]
        let category: String
    }

    static func extract(from post: Post) -> ItemSignals {
        // Server-enriched facets win when present; text extraction fills the gap.
        let text = [post.product.name, post.product.brand, post.caption]
            .joined(separator: " ")
            .lowercased()

        var vibes: [String] = []
        for (vibe, pattern) in vibeKeywords where text.matches(pattern) {
            vibes.append(vibe)
            if vibes.count >= 4 { break }
        }

        let category = post.category?.lowercased()
            ?? vibes.compactMap { vibeCategory[$0] }.first
            ?? "misc"

        return ItemSignals(vibes: vibes, category: category)
    }
}
