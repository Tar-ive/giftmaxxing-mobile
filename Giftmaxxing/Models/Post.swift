import Foundation

struct Post: Identifiable, Codable, Hashable {
    let id: String
    var user: String
    var ownerId: String?
    var authorImageUrl: String?
    var time: String
    var product: Product
    var caption: String
    var likes: Int
    var liked: Bool
    var saved: Bool
    var comments: [Comment]
    var commentCount: Int?
    var source: String?
    var url: String?
    var productUrl: String?
    var rec: Bool?
    var reason: String?
    // Facet + quality fields (server-enriched when present) consumed by the
    // on-device ranking pipeline (Services/Recommendation/).
    var recipient: String?
    var occasion: String?
    var category: String?
    var domain: String?
    /// The image's real width÷height, when the source told us.
    ///
    /// Instagram posts arrive with true dimensions, and cropping a 4:5 keepsake
    /// photo into a different 4:5 or letterboxing a 1:1 into 2:3 both destroy
    /// the composition the poster actually framed. Nil = unknown; the view
    /// falls back to measuring or to its editorial default.
    var aspectRatio: Double?
    var qualityScore: Double?
    var feedEligible: Bool?
    // A gift can be a THING or a YEAR OF SOMETHING (Netflix, Costco, Prime…).
    // "service" items render the branded service card and feed the
    // product-vs-service taste split (TasteProfileStore.giftTypeAffinity).
    var giftType: String?
    var serviceDuration: String?
    var contentType: String?
    var mediaUrl: String?
    var posterUrl: String?
    var music: UGCMusicTrack?
    // The story behind the gift — a maker's note, anecdote, or craftsmanship
    // detail (server-provided; GiftStory composes an honest fallback).
    var story: String?

    var isService: Bool { giftType == "service" }

    var displayCommentCount: Int {
        commentCount ?? comments.count
    }

    enum CodingKeys: String, CodingKey {
        case id, user, ownerId, authorImageUrl, time, product, caption, likes, liked, saved
        case comments, commentCount, source, url, productUrl, rec, reason
        case recipient, occasion, category, domain, qualityScore, feedEligible
        case giftType, serviceDuration
        case contentType, mediaUrl, posterUrl, music, story
    }

    init(
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
        story: String? = nil
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
    }
}

struct Comment: Identifiable, Codable, Hashable {
    let id: String
    var user: String
    var text: String
    var userId: String? = nil
    var authorImageUrl: String? = nil
    var createdAt: Double? = nil
}
