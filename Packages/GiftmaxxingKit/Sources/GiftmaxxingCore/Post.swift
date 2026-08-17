import Foundation

public struct Post: Identifiable, Codable, Hashable {
    public let id: String
    public var user: String
    public var ownerId: String?
    public var authorImageUrl: String?
    public var time: String
    public var product: Product
    public var caption: String
    public var likes: Int
    public var liked: Bool
    public var saved: Bool
    public var comments: [Comment]
    public var commentCount: Int?
    public var source: String?
    public var url: String?
    public var productUrl: String?
    public var rec: Bool?
    public var reason: String?
    // Facet + quality fields (server-enriched when present) consumed by the
    // on-device ranking pipeline (Services/Recommendation/).
    public var recipient: String?
    public var occasion: String?
    public var category: String?
    public var domain: String?
    /// The image's real width÷height, when the source told us.
    ///
    /// Instagram posts arrive with true dimensions, and cropping a 4:5 keepsake
    /// photo into a different 4:5 or letterboxing a 1:1 into 2:3 both destroy
    /// the composition the poster actually framed. Nil = unknown; the view
    /// falls back to measuring or to its editorial default.
    public var aspectRatio: Double?
    public var qualityScore: Double?
    public var feedEligible: Bool?
    // A gift can be a THING or a YEAR OF SOMETHING (Netflix, Costco, Prime…).
    // "service" items render the branded service card and feed the
    // product-vs-service taste split (TasteProfileStore.giftTypeAffinity).
    public var giftType: String?
    public var serviceDuration: String?
    public var contentType: String?
    public var mediaUrl: String?
    public var posterUrl: String?
    public var music: UGCMusicTrack?
    // The story behind the gift — a maker's note, anecdote, or craftsmanship
    // detail (server-provided; GiftStory composes an honest fallback).
    public var story: String?
    /// Capabilities verified from the merchant listing.
    public var productFeatures: [String]?

    public var isService: Bool { giftType == "service" }

    public var displayCommentCount: Int {
        commentCount ?? comments.count
    }

    public enum CodingKeys: String, CodingKey {
        case id, user, ownerId, authorImageUrl, time, product, caption, likes, liked, saved
        case comments, commentCount, source, url, productUrl, rec, reason
        case recipient, occasion, category, domain, qualityScore, feedEligible
        case giftType, serviceDuration
        case contentType, mediaUrl, posterUrl, music, story, productFeatures
    }

    public init(
        id: String,
        user: String,
        ownerId: String? = nil,
        authorImageUrl: String? = nil,
        time: String,
        product: Product,
        caption: String,
        likes: Int,
        liked: Bool = false,
        saved: Bool = false,
        comments: [Comment] = [],
        commentCount: Int? = nil,
        source: String? = nil,
        url: String? = nil,
        productUrl: String? = nil,
        rec: Bool? = nil,
        reason: String? = nil,
        recipient: String? = nil,
        occasion: String? = nil,
        category: String? = nil,
        domain: String? = nil,
        qualityScore: Double? = nil,
        feedEligible: Bool? = nil,
        giftType: String? = nil,
        serviceDuration: String? = nil,
        contentType: String? = nil,
        mediaUrl: String? = nil,
        posterUrl: String? = nil,
        music: UGCMusicTrack? = nil,
        story: String? = nil,
        productFeatures: [String]? = nil
    ) {
        self.id = id
        self.user = user
        self.ownerId = ownerId
        self.authorImageUrl = authorImageUrl
        self.time = time
        self.product = product
        self.caption = caption
        self.likes = likes
        self.liked = liked
        self.saved = saved
        self.comments = comments
        self.commentCount = commentCount
        self.source = source
        self.url = url
        self.productUrl = productUrl
        self.rec = rec
        self.reason = reason
        self.recipient = recipient
        self.occasion = occasion
        self.category = category
        self.domain = domain
        self.qualityScore = qualityScore
        self.feedEligible = feedEligible
        self.giftType = giftType
        self.serviceDuration = serviceDuration
        self.contentType = contentType
        self.mediaUrl = mediaUrl
        self.posterUrl = posterUrl
        self.music = music
        self.story = story
        self.productFeatures = productFeatures
    }
}

public struct Comment: Identifiable, Codable, Hashable {
    public let id: String
    public var user: String
    public var text: String
    public var userId: String? = nil
    public var authorImageUrl: String? = nil
    public var createdAt: Double? = nil
}
