import Foundation

// The story behind a gift — the anecdote/craftsmanship note surfaced by
// long-pressing a feed image (alt-text style) and in the detail sheet.
//
// Server-provided `Post.story` wins when present (Shopify ingests carry the
// maker's own product description). The fallback is composed ONLY from real
// metadata — provenance we can stand behind (marketplace type, service shape,
// the curator's reason) — never invented claims about who made what.
enum GiftStory {
    // Marketplaces whose sellers are independent makers/curators — the
    // "choose small businesses" signal for Thoughtfulness Points too.
    private static let independentMarketplaces: Set<String> = [
        "etsy.com", "etsy.me", "uncommongoods.com", "notonthehighstreet.com",
        "thegrommet.com", "minted.com", "society6.com",
    ]

    static func isSmallBusiness(_ post: Post) -> Bool {
        let domain = (post.domain ?? "").lowercased().replacingOccurrences(of: "www.", with: "")
        return independentMarketplaces.contains(domain)
            || independentMarketplaces.contains(where: { domain.hasSuffix("." + $0) })
    }

    // nil = nothing meaningful to tell (no overlay, no hint icon).
    static func story(for post: Post) -> String? {
        if let story = post.story?.trimmingCharacters(in: .whitespacesAndNewlines), !story.isEmpty {
            return story
        }

        var lines: [String] = []

        // The curator's why — skip merchant echoes ("Real find from ebay.com").
        if let reason = post.reason, !reason.isEmpty {
            let lower = reason.lowercased()
            let brand = post.product.brand.lowercased()
            let domain = (post.domain ?? "").lowercased()
            if (brand.isEmpty || !lower.contains(brand)) && (domain.isEmpty || !lower.contains(domain)) {
                lines.append(reason)
            }
        }

        if post.isService {
            let duration = post.serviceDuration ?? "a year"
            lines.append("Not a thing — \(duration) of something they'll actually use. A gift that renews every month instead of gathering dust.")
        } else if isSmallBusiness(post) {
            lines.append("Listed on \(marketplaceName(post)) — a marketplace of independent sellers, where most pieces are made or hand-picked by one person.")
        }

        let composed = lines.joined(separator: "\n\n")
        return composed.isEmpty ? nil : composed
    }

    private static func marketplaceName(_ post: Post) -> String {
        let domain = (post.domain ?? "").lowercased()
        if domain.contains("etsy") { return "Etsy" }
        if domain.contains("uncommongoods") { return "Uncommon Goods" }
        if domain.contains("notonthehighstreet") { return "Not On The High Street" }
        if domain.contains("grommet") { return "The Grommet" }
        if domain.contains("minted") { return "Minted" }
        if domain.contains("society6") { return "Society6" }
        return "an independent-maker marketplace"
    }
}
