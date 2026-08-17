import Foundation

public struct CuratedGiftCatalog: Codable {
    public let version: String
    public let sourceFile: String
    public let reviewedAt: String
    public let journeys: [CuratedGiftJourney]
    public let products: [CuratedGiftProduct]
    public let wrapKit: [CuratedGiftProduct]
}

public struct CuratedGiftJourney: Identifiable, Codable, Hashable {
    public let id: String
    public let sourcePostId: String
    public let sourceUrl: String
    public let title: String
    public let subtitle: String
    public let whySelected: String
    public let labels: [String]
    public let imageCount: Int
    public let productIds: [String]

    public var images: [String] {
        (1...max(imageCount, 1)).map {
            "bundle:///\(sourcePostId)-\(String(format: "%02d", $0)).jpg"
        }
    }

    public var sourcePost: Post {
        Post(
            id: "curated-source-\(sourcePostId)",
            user: "giftmaxxing",
            time: "Gift guide",
            product: Product(
                id: "curated-guide-\(id)",
                name: title,
                brand: "Gift guide",
                price: 0,
                was: nil,
                grad: .peach,
                emoji: "🎁",
                image: images.first,
                images: Array(images.dropFirst())
            ),
            caption: subtitle,
            likes: 0,
            source: "ugc",
            url: sourceUrl,
            reason: nil,
            category: labels.first,
            qualityScore: 1,
            feedEligible: true,
            contentType: "carousel",
            story: whySelected
        )
    }
}

public struct CuratedGiftProduct: Identifiable, Codable, Hashable {
    public enum PurchaseMode: String, Codable {
        case productPage
        case chooseVariant
        case configure
    }

    public let id: String
    public let name: String
    public let brand: String
    public let price: Double
    public let merchant: String
    public let productUrl: String
    public let image: String
    public let purchaseMode: PurchaseMode
    public let capabilities: [String]
    public let matchEvidence: String

    public var purchaseLabel: String {
        switch purchaseMode {
        case .configure: "Configure at \(merchant)"
        case .chooseVariant: "Choose at \(merchant)"
        case .productPage: "Open at \(merchant)"
        }
    }

    public var post: Post {
        Post(
            id: "curated-product-\(id)",
            user: merchant,
            time: "verified",
            product: Product(
                id: id,
                name: name,
                brand: brand,
                price: price,
                was: nil,
                grad: .peach,
                emoji: "🎁",
                image: image
            ),
            caption: matchEvidence,
            likes: 0,
            source: "curated-product",
            productUrl: productUrl,
            rec: true,
            reason: "Found in this gift guide",
            category: "curated",
            domain: merchant,
            qualityScore: 1,
            feedEligible: true,
            story: matchEvidence,
            productFeatures: capabilities
        )
    }
}

public final class CuratedGiftStore {
    public static let shared = CuratedGiftStore()
    public static let isPilotEnabled = true

    public let catalog: CuratedGiftCatalog

    public var sourcePosts: [Post] { catalog.journeys.map(\.sourcePost) }
    public var productPosts: [Post] {
        // Inspiration slides explain an idea; they are not merchant product
        // photos. Swipe cards therefore keep only verified listing imagery.
        catalog.products.map(\.post)
    }
    public var wrapPosts: [Post] { catalog.wrapKit.map(\.post) }
    /// Products admitted to taste-learning decks. Every card has a verified
    /// retailer destination and came through the reviewed curation manifest.
    public var challengeProducts: [Post] {
        productPosts.filter { post in
            guard let raw = post.productUrl, let url = URL(string: raw) else { return false }
            return post.product.price > 0 && ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        }
    }

    public var feedPosts: [Post] {
        unique(catalog.journeys.flatMap { [$0.sourcePost] + products(for: $0).map(\.post) } + wrapPosts)
    }

    private init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "curated-gift-journeys", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CuratedGiftCatalog.self, from: data) else {
            preconditionFailure("Missing or invalid curated-gift-journeys.json")
        }
        catalog = decoded
    }

    public func search(_ query: String) -> [Post] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return productPosts + wrapPosts }
        return (productPosts + wrapPosts).filter { post in
            let product = catalog.products.first { "curated-product-\($0.id)" == post.id }
                ?? catalog.wrapKit.first { "curated-product-\($0.id)" == post.id }
            let haystack = [post.product.name, post.product.brand, post.caption]
                + (product?.capabilities ?? [])
            let normalized = haystack.joined(separator: " ").lowercased()
            return terms.allSatisfy(normalized.contains)
        }
    }

    public func feed(query: String) -> [Post] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return feedPosts }
        let journeys = catalog.journeys.filter { journey in
            let normalized = ([journey.title, journey.subtitle] + journey.labels)
                .joined(separator: " ").lowercased()
            return terms.contains { normalized.contains($0) }
        }
        let matched = journeys.flatMap { [$0.sourcePost] + products(for: $0).map(\.post) }
        let queryProducts = search(query)
        return unique(matched + queryProducts)
    }

    public func products(for journey: CuratedGiftJourney) -> [CuratedGiftProduct] {
        let byId = Dictionary(uniqueKeysWithValues: catalog.products.map { ($0.id, $0) })
        return journey.productIds.compactMap { byId[$0] }
    }

    public func journey(containing postId: String) -> CuratedGiftJourney? {
        if let journey = catalog.journeys.first(where: { $0.sourcePost.id == postId }) { return journey }
        let productId = postId.replacingOccurrences(of: "curated-product-", with: "")
        return catalog.journeys.first { $0.productIds.contains(productId) }
    }

    public func journeys(containingProductId productId: String) -> [CuratedGiftJourney] {
        catalog.journeys.filter { $0.productIds.contains(productId) }
    }

    private func unique(_ posts: [Post]) -> [Post] {
        var seen = Set<String>()
        return posts.filter { seen.insert($0.id).inserted }
    }
}
