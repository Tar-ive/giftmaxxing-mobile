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

    static func isPinterestUrl(_ url: String) -> Bool {
        url.range(of: "pinterest\\.[a-z]", options: [.regularExpression, .caseInsensitive]) != nil
            || url.range(of: "//pin\\.it/", options: [.regularExpression, .caseInsensitive]) != nil
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
            return url
        }
        return URL(string: searchUrl(query: query.isEmpty ? "gifts" : query))
    }
}
