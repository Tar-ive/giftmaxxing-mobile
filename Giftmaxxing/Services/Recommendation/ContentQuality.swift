import Foundation

// On-device port of the server's deterministic content-quality classifier
// (infra/src/quality.mjs). Stage-1 gate of the local ranking pipeline: decides
// whether an item is a single BUYABLE product (feed-eligible) or editorial /
// listicle / recipe / spam content. Pure function of fields every item already
// carries (title, domain, link, price), so it runs at zero cost on device and
// keeps working even when the server sheds AI routes in degraded mode.

enum ContentType: String {
    case singleProduct = "single_product"
    case giftGuide = "gift_guide"
    case editorial
    case recipe
    case seasonal
    case spam
}

struct ContentQuality {
    let contentType: ContentType
    let feedEligible: Bool
    let qualityScore: Double

    // Head-domain reputation (mirrors RETAILER in quality.mjs).
    private static let retailerDomains: Set<String> = [
        "etsy.com", "etsy.me", "sephora.com", "seph.me", "thegrommet.com", "anthropologie.com",
        "papersource.com", "ebay.com", "lowes.com", "urbanoutfitters.com", "uncommongoods.com",
        "altardstate.com", "amazon.com", "amzn.to", "poshmark.com", "pukkagifts.uk", "kisaf.com",
        "nordstrom.com", "target.com", "walmart.com", "madewell.com", "ulta.com", "westelm.com",
        "crateandbarrel.com", "potterybarn.com", "bathandbodyworks.com", "society6.com",
        "redbubble.com", "minted.com", "notonthehighstreet.com", "cb2.com", "wayfair.com",
    ]

    // Blogs / SEO-content / ad-farms / non-commerce (mirrors CONTENT in quality.mjs).
    private static let contentDomains: Set<String> = [
        "sites.google.com", "thecanadianguy.com", "loveandlavender.com", "blossomhomelife.com",
        "minimizemymess.com", "within-yourhome.com", "everydaysavvy.com", "newtrendsetter.com",
        "goodmomliving.com", "sunshinencoffeemornings.com", "mindfulnessinspo.com",
        "thecreativebite.com", "luxeandleanblog.com", "moritzfinedesigns.com", "greenweddingshoes.com",
        "m.youtube.com", "youtube.com", "flickr.com", "linktw.in", "presentatlas.com",
        "thelifestyleloft.blogspot.com",
    ]

    private static let recipeDomain = "(rasamalaysia|allrecipes|foodnetwork|seriouseats|delish|tasty|recipe)"
    private static let contentSuffix = "\\.(blogspot|wordpress|wixsite|substack)\\.com$|\\.blog$"

    // Caption signals (mirrors quality.mjs regexes).
    private static let startsNumber = "^\\s*\\d{1,3}\\b"
    private static let nGifts = "\\b\\d{1,3}\\s*\\+?\\s*[\\w\\s]{0,20}?\\bgifts?\\b"
    private static let giftGuide = "\\bgift\\s+(guide|ideas?|lists?|roundups?)\\b"
    private static let giftIdea = "\\bgift\\s+ideas?\\b"
    private static let giftsFor = "\\bgifts\\s+(for|under|that|your|to|she|he|who)\\b"
    private static let diyGifts = "\\bdiy\\s+gifts?\\b"
    private static let adjGifts = "\\b(best|top|unique|prettiest|coolest|cutest|thoughtful|perfect|ultimate|cool|cheap|inexpensive|budget|last[- ]minute|amazing)\\b[\\w\\s]{0,15}\\bgifts\\b"
    private static let editorialWords = "\\b(ideas|inspiration|inspo|roundup|how to|tutorial|diy)\\b"
    private static let recipeWords = "\\b(recipe|recipes|soup|salad|casserole|smoothie|cocktail|appetizers?|brunch)\\b"
    private static let seasonalPromo = "\\b(father'?s|mother'?s|valentine'?s|christmas|halloween|thanksgiving)\\s+day\\b.*\\b(is|coming|almost|here|sale|\\d{1,2}(st|nd|rd|th)?)\\b"
    private static let pdpPath = "/(dp|gp/product|listing|products?|p|item|sku)/"

    private enum DomainClass { case retailer, content, recipe, unknown }

    private static func domainClass(_ domain: String?) -> DomainClass {
        var d = (domain ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        if d.hasPrefix("www.") { d = String(d.dropFirst(4)) }
        if d.isEmpty { return .unknown }
        if d.matches(recipeDomain) { return .recipe }
        if contentDomains.contains(d) || d.matches(contentSuffix) { return .content }
        if retailerDomains.contains(d) || retailerDomains.contains(where: { d.hasSuffix("." + $0) }) { return .retailer }
        return .unknown
    }

    static func classify(title: String?, domain: String?, link: String?, price: Double?) -> ContentQuality {
        let t = title ?? ""
        let lt = t.lowercased()
        let dc = domainClass(domain)
        let p = price ?? 0

        func result(_ type: ContentType, _ score: Double) -> ContentQuality {
            ContentQuality(
                contentType: type,
                feedEligible: type == .singleProduct,
                qualityScore: max(0, min(1, score))
            )
        }

        // 1) Recipes — never giftable here.
        if dc == .recipe || (lt.matches(recipeWords) && p <= 0) {
            return result(.recipe, 0.05)
        }

        // 2) Listicles / gift guides — kept off the scroll feed.
        let numbered = t.matches(startsNumber) || t.matches(nGifts)
        let guide = t.matches(giftGuide) || t.matches(giftIdea) || t.matches(giftsFor)
            || t.matches(diyGifts) || t.matches(adjGifts)
        if numbered || guide {
            return result(.giftGuide, 0.2)
        }

        // 3) Known content/blog/spam domains.
        if dc == .content {
            return result(.spam, 0.08)
        }

        // 4) Seasonal promos / banners with no product.
        if lt.matches(seasonalPromo) && p <= 0 {
            return result(.seasonal, 0.1)
        }

        // 5) Generic editorial with no price.
        if lt.matches(editorialWords) && p <= 0 && dc != .retailer {
            return result(.editorial, 0.15)
        }

        // 6) Otherwise: a single product — score by buy-signal strength.
        var q = 0.5
        if p > 0 { q += 0.3 }
        if dc == .retailer { q += 0.2 }
        if (link ?? "").matches(pdpPath) { q += 0.1 }
        if !t.isEmpty && t.count <= 60 { q += 0.05 }
        if dc == .unknown && p <= 0 { q -= 0.15 }
        return result(.singleProduct, q)
    }
}

extension String {
    // Case-insensitive regex test used across the local ranking pipeline.
    func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
