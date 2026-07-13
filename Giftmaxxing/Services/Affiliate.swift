import Foundation

// Amazon Associates affiliate helpers — port of web/lib/affiliate.ts.
// Every outbound product link carries the associate tag; items without a
// usable retailer URL fall back to a tagged Amazon search.
enum Affiliate {
    static let associateTag = "giftmaxxingde-20"
    static let marketplace = "https://www.amazon.com"

    static func isValidAsin(_ asin: String) -> Bool {
        asin.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil
    }

    static func amazonUrl(asin: String) -> String {
        let normalized = asin.trimmingCharacters(in: .whitespaces).uppercased()
        guard isValidAsin(normalized) else {
            return searchUrl(query: asin)
        }
        return "\(marketplace)/dp/\(normalized)?tag=\(associateTag)"
    }

    static func searchUrl(query: String) -> String {
        let q = query.trimmingCharacters(in: .whitespaces)
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "gifts"
        return "\(marketplace)/s?k=\(encoded)&tag=\(associateTag)"
    }

    static func isAmazonUrl(_ url: String) -> Bool {
        url.range(of: "amazon\\.[a-z]", options: [.regularExpression, .caseInsensitive]) != nil
            || url.range(of: "amzn\\.to/", options: [.regularExpression, .caseInsensitive]) != nil
            || url.range(of: "//a\\.co/", options: [.regularExpression, .caseInsensitive]) != nil
    }

    // Pull a 10-char ASIN out of any Amazon URL (parity with web extractAsin):
    // /dp/, /gp/product/, /gp/aw/d/ path segments, or the bare ASIN itself.
    static func extractAsin(from input: String) -> String? {
        let s = input.trimmingCharacters(in: .whitespaces).uppercased()
        if isValidAsin(s) { return s }
        guard let range = s.range(
            of: "/(?:DP|GP/PRODUCT|GP/AW/D)/([A-Z0-9]{10})",
            options: .regularExpression
        ) else { return nil }
        return String(s[range].suffix(10))
    }

    // Amazon URLs from server enrichment may arrive untagged — rebuild them as
    // a clean tagged /dp link (web outboundAffiliateUrl does the same). Non-
    // Amazon URLs pass through untouched.
    static func retag(_ url: URL) -> URL {
        guard isAmazonUrl(url.absoluteString) else { return url }
        if let asin = extractAsin(from: url.absoluteString),
           let rebuilt = URL(string: amazonUrl(asin: asin)) {
            return rebuilt
        }
        // No ASIN (search / storefront / shortlink): make sure the tag rides along.
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name == "tag" }) {
            items.append(URLQueryItem(name: "tag", value: associateTag))
            components.queryItems = items
        }
        return components.url ?? url
    }

    // Hosts the Amazon iOS app claims as universal links (verified against the
    // live apple-app-site-association files — see docs/amazon-app-linking.md).
    // amzn.to is Bitly-managed and never opens the app, so it stays browser-only.
    static func isAppLinkEligible(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "a.co" || host == "www.a.co" { return true }
        return host.range(of: "(^|\\.)amazon\\.[a-z.]+$", options: .regularExpression) != nil
    }

    static func isPinterestUrl(_ url: String) -> Bool {
        url.range(of: "pinterest\\.[a-z]", options: [.regularExpression, .caseInsensitive]) != nil
            || url.range(of: "//pin\\.it/", options: [.regularExpression, .caseInsensitive]) != nil
    }

    // ── "Find it at" major-US-retailer links ─────────────────────────────────
    // The catalog's organic links skew Etsy/eBay/Pinterest; US shoppers buy
    // from Amazon/Target/Walmart. Every product gets one-tap search deep links
    // into those stores so a match is always buyable somewhere familiar.

    struct RetailerSearchLink: Identifiable, Hashable {
        let name: String
        let url: URL
        var id: String { name }
    }

    static func retailerSearchLinks(for post: Post) -> [RetailerSearchLink] {
        retailerSearchLinks(
            name: post.product.name,
            brand: post.product.brand,
            currentUrl: post.productUrl ?? post.url
        )
    }

    static func retailerSearchLinks(
        name: String,
        brand: String? = nil,
        currentUrl: String? = nil
    ) -> [RetailerSearchLink] {
        // Scraped titles run long (eBay SEO strings) — the first few words are
        // the product; the tail just narrows retailer search to zero results.
        var query = name
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .prefix(8)
            .joined(separator: " ")
        if let brand = brand?.trimmingCharacters(in: .whitespaces),
           !brand.isEmpty, !brand.contains("."), // domain-shaped "brands" (etsy.me) add noise
           !query.localizedCaseInsensitiveContains(brand) {
            query = "\(brand) \(query)"
        }
        guard !query.isEmpty else { return [] }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "gifts"
        let current = (currentUrl ?? "").lowercased()

        var links: [RetailerSearchLink] = []
        // Skip the store the product already links to — the main CTA covers it.
        if !isAmazonUrl(current), let url = URL(string: searchUrl(query: query)) {
            links.append(RetailerSearchLink(name: "Amazon", url: url))
        }
        if !current.contains("target.com"),
           let url = URL(string: "https://www.target.com/s?searchTerm=\(encoded)") {
            links.append(RetailerSearchLink(name: "Target", url: url))
        }
        if !current.contains("walmart.com"),
           let url = URL(string: "https://www.walmart.com/search?q=\(encoded)") {
            links.append(RetailerSearchLink(name: "Walmart", url: url))
        }
        return links
    }

    // Best outbound URL for a post's product (mirrors web outboundAffiliateUrl):
    // a real retailer URL passes through (Amazon links get our tag via search
    // fallback upstream); missing/Pinterest/"#" links become a tagged Amazon
    // search for the product name + brand so every click is monetized.
    static func productUrl(for post: Post) -> URL? {
        let query = [post.product.name, post.product.brand]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if let raw = post.productUrl,
           !raw.isEmpty, raw != "#", !isPinterestUrl(raw),
           let url = URL(string: raw),
           url.scheme?.hasPrefix("http") == true {
            // Web parity: Amazon URLs are rebuilt around their ASIN so the tag
            // is always present; ASIN-less Amazon links fall back to a tagged
            // search; other retailers pass through untouched.
            if isAmazonUrl(raw) {
                if let asin = extractAsin(from: raw), let rebuilt = URL(string: amazonUrl(asin: asin)) {
                    return rebuilt
                }
                return URL(string: searchUrl(query: query.isEmpty ? "gifts" : query))
            }
            return url
        }
        return URL(string: searchUrl(query: query.isEmpty ? "gifts" : query))
    }
}
