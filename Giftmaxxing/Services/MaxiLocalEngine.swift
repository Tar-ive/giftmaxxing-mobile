import Foundation

// Local Maxi intent engine — iOS port of web/lib/maxi.ts respond(). Runs when
// the agent API is unreachable (or the user is signed out) so Maxi ALWAYS
// answers. Product search runs over the fetched feed catalog.
enum MaxiLocalEngine {
    struct Reply {
        var say: String
        var products: [MaxiProduct]
        var chips: [String]
    }

    // Openers that START THE JOB rather than run a search. The old chips
    // ("Gift under $40", "Something cozy") were queries — they got you a list
    // and left you where you started. Naming a person is what lets Maxi pull
    // up what it already knows and work a brief.
    static let seedChips = ["My mom", "A friend's birthday", "My partner", "Just browsing"]

    // Mirror of web CATEGORY_SYNONYMS.
    private static let categorySynonyms: [String: [String]] = [
        "home": ["home", "cozy", "decor", "candle", "apartment", "living", "blanket"],
        "kitchen": ["kitchen", "cook", "baking", "bake", "chef", "foodie", "food", "coffee", "tea"],
        "plants": ["plant", "garden", "green", "flower", "botanical"],
        "jewelry": ["jewelry", "jewellery", "ring", "necklace", "bracelet", "charm", "gold"],
        "art": ["art", "print", "paint", "creative", "craft", "diy", "photo"],
        "vintage": ["vintage", "retro", "antique", "old school", "nostalgic"],
        "wellness": ["wellness", "self care", "selfcare", "spa", "relax", "sleep", "calm"],
        "sports": ["sport", "fitness", "grill", "bbq", "outdoors", "hockey"],
        "tech": ["tech", "gadget", "useful", "organize", "practical", "gear"],
        "travel": ["travel", "beach", "summer", "trip", "coastal", "nautical"],
        "party": ["party", "fun", "celebrate", "whimsical"],
    ]

    // Mirror of web RECIPIENT_HINT.
    private static let recipientHint: [String: String] = [
        "mom": "home", "mother": "home", "grandma": "home",
        "dad": "sports", "father": "sports", "grandpa": "sports",
        "girlfriend": "jewelry", "wife": "jewelry",
        "boyfriend": "tech", "husband": "tech", "brother": "tech",
        "sister": "art", "bestie": "art", "friend": "home",
    ]

    // Mirror of web parseBudget().
    static func parseBudget(_ text: String) -> Double? {
        let patterns = [
            "\\$\\s?(\\d{1,4})",
            "(?:under|below|less than|max(?:imum)?|up to|within)\\s+\\$?(\\d{1,4})",
            "(\\d{1,4})\\s?(?:dollars|bucks|usd)",
        ]
        for pattern in patterns {
            if let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let digits = text[match].components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if let value = Double(digits), value >= 1 { return value }
            }
        }
        return nil
    }

    static func parseCategory(_ text: String) -> String? {
        let lower = text.lowercased()
        for (recipient, category) in recipientHint where lower.contains(recipient) {
            return category
        }
        for (category, synonyms) in categorySynonyms {
            if synonyms.contains(where: { lower.contains($0) }) { return category }
        }
        return nil
    }

    static func respond(to input: String, catalog: [Post]) -> Reply {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()

        // Greeting-only turns.
        if lower.range(of: "^(hi|hey|hello|yo|sup)[!. ]*$", options: .regularExpression) != nil {
            return Reply(
                say: "Hey! Tell me a budget, a vibe, or who the gift is for — I'll pull ideas.",
                products: [],
                chips: seedChips
            )
        }

        let budget = parseBudget(lower)
        let category = parseCategory(lower)
        let wantsDeal = lower.contains("deal") || lower.contains("discount") || lower.contains("sale")

        var matches = catalog
        if let budget {
            matches = matches.filter { $0.product.price <= budget }
        }
        if let category {
            matches = matches.filter { post in
                let haystack = "\(post.product.name) \(post.caption) \(post.category ?? "")".lowercased()
                return haystack.contains(category)
                    || (categorySynonyms[category] ?? []).contains(where: { haystack.contains($0) })
            }
        }
        if wantsDeal {
            let discounted = matches.filter { $0.product.hasDiscount }
            if !discounted.isEmpty { matches = discounted }
        }
        if matches.isEmpty { matches = catalog }

        let picks = Array(matches.shuffled().prefix(6)).map { post in
            MaxiProduct(
                postId: post.id,
                title: post.product.name,
                price: post.product.price,
                brand: post.product.brand,
                image: post.product.image,
                category: post.category
            )
        }

        var sayParts: [String] = []
        if wantsDeal {
            sayParts.append("Here are the best deals I could find")
        } else {
            sayParts.append("Here's what I found")
        }
        if let category { sayParts.append("for \(category)") }
        if let budget { sayParts.append("under $\(Int(budget))") }
        let say = picks.isEmpty
            ? "I couldn't find a match for that — try a budget like \"under $50\" or a vibe like \"cozy\"."
            : sayParts.joined(separator: " ") + ". Tap one to see it, or refine the vibe!"

        return Reply(
            say: say,
            products: picks,
            chips: picks.isEmpty ? seedChips : ["Cheaper options", "Something cozy", "More like these"]
        )
    }
}
