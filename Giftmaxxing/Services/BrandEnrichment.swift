import Foundation
import GiftmaxxingCore

// Brand enrichment — port of web/lib/brand-enrichment.ts. Flat platform
// brands (e.g. "Etsy") become specific seller/brand names parsed from the
// title, else a deterministic category-appropriate brand, so the Brands tab
// has real diversity.
enum BrandEnrichment {
    private static let categoryBrands: [String: [String]] = [
        "jewelry": ["Mejuri", "Catbird", "Kendra Scott"],
        "home": ["West Elm", "Anthropologie Home", "CB2"],
        "plants": ["The Sill", "Bloomscape", "Terrain"],
        "vintage": ["Chairish", "1stDibs", "Etsy Vintage"],
        "art": ["Society6", "Minted", "Saatchi Art"],
        "kitchen": ["Our Place", "Le Creuset", "Material"],
        "travel": ["Away", "Paravel", "Tumi"],
        "tech": ["Anker", "Twelve South", "Native Union"],
        "wellness": ["Vitruvi", "Aesop", "Herbivore"],
        "sports": ["Tracksmith", "Outdoor Voices", "Cotopaxi"],
        "gifts": ["Uncommon Goods", "Rifle Paper Co.", "Poketo"],
    ]

    private static func hash(_ s: String) -> Int {
        var h: UInt32 = 0
        for scalar in s.unicodeScalars {
            h = h &* 31 &+ scalar.value
        }
        return Int(h)
    }

    static func enrich(brand: String, title: String, category: String?, id: String) -> String {
        // Specific (non-platform) brands pass through.
        guard brand.caseInsensitiveCompare("Etsy") == .orderedSame || brand.isEmpty else {
            return brand
        }

        // "Etsy seller <Name>" in the title.
        if let range = title.range(of: "Etsy seller (\\w+)", options: [.regularExpression, .caseInsensitive]) {
            let matched = String(title[range])
            if let seller = matched.components(separatedBy: " ").last, !seller.isEmpty {
                return seller
            }
        }

        // Deterministic category fallback.
        if let category, let brands = categoryBrands[category.lowercased()] {
            return brands[hash(id) % brands.count]
        }

        return brand.isEmpty ? "Giftmaxxing" : brand
    }

    static func enrich(post: Post) -> String {
        enrich(
            brand: post.product.brand,
            title: post.product.name,
            category: post.category,
            id: post.id
        )
    }
}
