import Foundation
import GiftmaxxingCore

// Turn a pasted product URL (SHEIN, Target, Walmart, Sephora, HEB, a Shopify
// store, anything) into a Post you can drop into a Gift Board and send as a
// swipe deck. The fetch runs ON DEVICE — the user's own IP + a Safari-like
// UA — so retailer bot-walls that block our cloud scrapers usually still serve
// the Open Graph tags meant for social crawlers. Whatever we can't read, we
// synthesize honestly from the URL itself, so a hand-added link ALWAYS becomes
// a usable card (name + a working "View" link); the image is a bonus.
enum LinkIngest {

    struct Meta {
        var title: String?
        var productName: String?  // JSON-LD Product name — the most reliable
        var image: String?
        var price: Double?
        var siteName: String?
    }

    /// Build a Post from a raw pasted string. Returns nil only if it isn't a URL.
    static func post(from raw: String) async -> Post? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              let scheme = comps.scheme, scheme.hasPrefix("http"),
              let host = comps.host else { return nil }
        // Keep the original for opening; use it verbatim as productUrl.
        guard let url = comps.url else { return nil }

        let meta = await fetchMeta(url)

        let host2 = host.lowercased()
        let merchant = brandName(host2)

        // The scraped title can be a bot-wall interstitial ("Pardon Our
        // Interruption", "Access Denied") or a site tagline used as og:title
        // ("SHEIN.com is mainly design and produce fashion clothing…") — neither
        // is the product. Fall back to the URL slug in those cases. The
        // JSON-LD product name (when present) is the most reliable, so prefer it.
        let ogTitle = cleanTitle(meta.title, siteName: meta.siteName ?? merchant)
        let blocked = ogTitle.map(isBlockedTitle) ?? false
        let generic = ogTitle.map { isGenericTitle($0, host: host2) } ?? false
        let name = meta.productName
            ?? (ogTitle.flatMap { (!blocked && !generic) ? $0 : nil })
            ?? slugTitle(url)
            ?? merchant
        // A bot-wall page's og:image is the block-page art, not the product —
        // drop it so we show a clean gradient card instead of a captcha image.
        let image = blocked ? nil : meta.image

        let id = "link-" + stableHashHex(url.absoluteString)
        let seed = stableHash(host2 + name)
        let grads = GradientStyle.allCases
        let grad = grads[Int(seed % UInt64(grads.count))]

        let product = Product(
            id: id,
            name: name,
            brand: merchant,
            price: meta.price ?? 0,
            grad: grad,
            emoji: "🎁",
            image: image
        )

        return Post(
            id: id,
            user: merchant,
            time: "",
            product: product,
            caption: "",
            likes: 0,
            source: "link",
            url: url.absoluteString,
            productUrl: url.absoluteString,
            domain: host2,
            // Hand-added: the user vouched for it — never gate it out of their
            // own deck. A neutral quality so it ranks sanely in "For me" swipes.
            qualityScore: 0.7,
            feedEligible: true,
            giftType: "product"
        )
    }

    // MARK: - Metadata fetch (best-effort)

    static func fetchMeta(_ url: URL) async -> Meta {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
              let html = String(data: data.prefix(600_000), encoding: .utf8)
                ?? String(data: data.prefix(600_000), encoding: .isoLatin1)
        else { return Meta() }

        let base = http.url ?? url
        return Meta(
            title: metaContent(html, properties: ["og:title", "twitter:title"]) ?? htmlTitle(html),
            productName: jsonLdProductName(html),
            image: absolutize(
                metaContent(html, properties: ["og:image:secure_url", "og:image", "twitter:image", "twitter:image:src"])
                    ?? jsonLdImage(html),
                base: base
            ),
            price: parsePrice(
                metaContent(html, properties: ["product:price:amount", "og:price:amount"])
                    ?? itempropContent(html, "price")
                    ?? jsonLdPrice(html)
            ),
            siteName: metaContent(html, properties: ["og:site_name"])
        )
    }

    // MARK: - Title quality

    private static let blockedTitleMarkers = [
        "pardon our interruption", "access denied", "attention required",
        "just a moment", "are you a robot", "robot check", "captcha",
        "verify you are human", "request unsuccessful", "security check",
        "enable javascript", "403 forbidden", "site maintenance",
        "access to this page has been denied",
    ]

    // A bot-wall / interstitial page title, not the product.
    static func isBlockedTitle(_ title: String) -> Bool {
        let t = title.lowercased()
        return blockedTitleMarkers.contains { t.contains($0) }
    }

    // A site tagline used as og:title ("SHEIN.com is mainly design and produce
    // fashion clothing…", "Official Site | …") — real page, wrong text.
    static func isGenericTitle(_ title: String, host: String) -> Bool {
        let t = title.lowercased()
        let generic = [
            " is mainly ", "official site", "official online store",
            "official store", "free shipping on", "shop the latest",
            "online shopping", "buy online",
        ]
        if generic.contains(where: { t.contains($0) }) { return true }
        // Just the bare site name ("Sephora") offers nothing over the slug.
        let root = host.replacingOccurrences(of: "www.", with: "").split(separator: ".").first.map(String.init) ?? host
        return t == root || t == root + ".com"
    }

    // The Product name from a JSON-LD block, if this page declares one. We only
    // trust a "name" that sits in a blob also mentioning "Product", so we don't
    // pick up the Organization/WebSite name.
    private static func jsonLdProductName(_ html: String) -> String? {
        guard html.range(of: "\"@type\"", options: .caseInsensitive) != nil else { return nil }
        // Find a Product type declaration, then the nearest following "name".
        let pattern = "\"@type\"\\s*:\\s*\"Product\"[\\s\\S]{0,600}?\"name\"\\s*:\\s*\"([^\"]{2,140})\""
        if let m = firstMatch(pattern, in: html) { return decodeEntities(m) }
        // Some feeds order name before @type.
        let pattern2 = "\"name\"\\s*:\\s*\"([^\"]{2,140})\"[\\s\\S]{0,200}?\"@type\"\\s*:\\s*\"Product\""
        return firstMatch(pattern2, in: html).map(decodeEntities)
    }

    // MARK: - HTML scraping (regex — no parser dependency)

    private static func metaContent(_ html: String, properties: [String]) -> String? {
        for prop in properties {
            // <meta property="og:image" content="..."> OR name="..." in either order.
            let patterns = [
                "<meta[^>]+(?:property|name)=[\"']\(NSRegularExpression.escapedPattern(for: prop))[\"'][^>]+content=[\"']([^\"']+)[\"']",
                "<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+(?:property|name)=[\"']\(NSRegularExpression.escapedPattern(for: prop))[\"']",
            ]
            for pattern in patterns {
                if let m = firstMatch(pattern, in: html), !m.isEmpty {
                    return decodeEntities(m)
                }
            }
        }
        return nil
    }

    private static func itempropContent(_ html: String, _ prop: String) -> String? {
        let pattern = "<meta[^>]+itemprop=[\"']\(prop)[\"'][^>]+content=[\"']([^\"']+)[\"']"
        return firstMatch(pattern, in: html).map(decodeEntities)
    }

    private static func htmlTitle(_ html: String) -> String? {
        firstMatch("<title[^>]*>([^<]+)</title>", in: html).map(decodeEntities)
    }

    // First "image" and "price" inside any JSON-LD blob — cheap and forgiving.
    private static func jsonLdImage(_ html: String) -> String? {
        firstMatch("\"image\"\\s*:\\s*\"([^\"]+)\"", in: html)
            ?? firstMatch("\"image\"\\s*:\\s*\\[\\s*\"([^\"]+)\"", in: html)
    }
    private static func jsonLdPrice(_ html: String) -> String? {
        firstMatch("\"price\"\\s*:\\s*\"?([0-9]+(?:\\.[0-9]{1,2})?)\"?", in: html)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = re.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    // MARK: - Cleaners

    private static func cleanTitle(_ raw: String?, siteName: String?) -> String? {
        guard var t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        // Trim a trailing " | SHEIN USA" / " - Target" site suffix when the
        // title is long enough to survive without it.
        for sep in [" | ", " – ", " — ", " - "] {
            if let range = t.range(of: sep, options: .backwards) {
                let head = String(t[..<range.lowerBound])
                let tail = t[range.upperBound...].lowercased()
                if head.count >= 12,
                   let site = siteName?.lowercased(), tail.contains(site) || tail.count <= 18 {
                    t = head
                }
            }
        }
        return String(t.prefix(120))
    }

    // Fallback name from the URL path slug, e.g.
    // ".../Fashion-Solid-Color-Mini-Shoulder-Bag-...-p-27870728.html" →
    // "Fashion Solid Color Mini Shoulder Bag ...".
    private static func slugTitle(_ url: URL) -> String? {
        let segments = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        // Prefer the longest wordy segment (product slugs are the long ones).
        let candidate = segments
            .map { $0.replacingOccurrences(of: ".html", with: "").replacingOccurrences(of: ".htm", with: "") }
            .max(by: { wordScore($0) < wordScore($1) })
        guard var slug = candidate else { return nil }
        // Drop trailing "-p-123456" / "-A-95060177" style id tails.
        slug = slug.replacingOccurrences(
            of: "[-_](?:p|a|id|dp|prod|product)?[-_]?[0-9]{4,}$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let words = slug
            .replacingOccurrences(of: "[-_+]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "%20", with: " ")
            .split(separator: " ")
            .filter { !$0.allSatisfy(\.isNumber) }
        guard !words.isEmpty else { return nil }
        let title = words.map { $0.prefix(1).uppercased() + String($0.dropFirst()) }.joined(separator: " ")
        return title.isEmpty ? nil : String(title.prefix(90))
    }

    // How "slug-like" a path segment is (more separators + letters = more likely
    // the human-readable product name rather than an id or a category).
    private static func wordScore(_ s: String) -> Int {
        let separators = s.filter { $0 == "-" || $0 == "_" }.count
        let letters = s.filter(\.isLetter).count
        return separators * 3 + letters
    }

    private static func brandName(_ host: String) -> String {
        var h = host
        for prefix in ["www.", "us.", "shop.", "m.", "store."] where h.hasPrefix(prefix) {
            h.removeFirst(prefix.count)
        }
        // second-level label: "shein" from "shein.com", "willowavenue" from
        // "niyamat.willowavenue.shop".
        let labels = h.split(separator: ".").map(String.init)
        let core = labels.count >= 2 ? labels[labels.count - 2] : (labels.first ?? h)
        if let known = knownBrands[core] { return known }
        return core.prefix(1).uppercased() + String(core.dropFirst())
    }

    private static let knownBrands: [String: String] = [
        "shein": "SHEIN", "heb": "H-E-B", "walmart": "Walmart", "target": "Target",
        "sephora": "Sephora", "amazon": "Amazon", "etsy": "Etsy", "ebay": "eBay",
        "bestbuy": "Best Buy", "nordstrom": "Nordstrom", "ulta": "Ulta",
    ]

    private static func absolutize(_ value: String?, base: URL) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if value.hasPrefix("http") { return value }
        if value.hasPrefix("//") { return "https:" + value }
        return URL(string: value, relativeTo: base)?.absoluteString
    }

    private static func parsePrice(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        // Keep digits + first decimal point; drop currency symbols/thousands.
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        guard let value = Double(cleaned), value > 0, value < 100_000 else { return nil }
        return value
    }

    private static func decodeEntities(_ s: String) -> String {
        var out = s
        let map = ["&amp;": "&", "&#39;": "'", "&#039;": "'", "&apos;": "'",
                   "&quot;": "\"", "&#34;": "\"", "&lt;": "<", "&gt;": ">",
                   "&nbsp;": " ", "&#8217;": "’", "&#8216;": "‘", "&#8211;": "–"]
        for (k, v) in map { out = out.replacingOccurrences(of: k, with: v) }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Stable, launch-independent hash (djb2), so re-adding the same URL yields
    // the same id and dedupes inside a board.
    private static func stableHash(_ s: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in s.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return hash
    }
    private static func stableHashHex(_ s: String) -> String {
        String(stableHash(s), radix: 16)
    }
}
