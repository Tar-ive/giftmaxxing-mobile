import Foundation

public struct APIPost: Codable {
    public let postId: String
    public var author: String?
    public var authorName: String?
    public var authorImageUrl: String?
    public var ownerId: String?
    public var createdAt: Double?
    public var likes: Int?
    public var comments: Int?
    public var caption: String?
    public var source: String?
    public var url: String?
    public var productUrl: String?
    public var rec: Bool?
    public var reason: String?
    public var recipient: String?
    public var occasion: String?
    public var category: String?
    public var status: String?
    public var product: APIProduct?
    // Serve-time enrichment attached by the backend feed/recommendation routes
    // (classifyPin output + raw commerce fields) — used by the on-device ranker.
    public var domain: String?
    public var merchant: String?
    public var price: Double?
    public var vibes: [String]?
    public let aspectRatio: Double?
    public var qualityScore: Double?
    public var contentType: String?
    public var mediaUrl: String?
    public var mediaUrls: [String]?
    public var posterUrl: String?
    public var music: UGCMusicTrack?
    public var recentComments: [Comment]? = nil
    public var feedEligible: Bool?
    // Products vs gift-able services (a year of Netflix, a Costco membership…).
    public var giftType: String?
    public var serviceDuration: String?
    // Maker's note / anecdote / craftsmanship detail (Shopify ingests carry
    // the product description; long-press on the feed image reveals it).
    public var story: String?
    public var productFeatures: [String]?

    public init(
        postId: String,
        author: String? = nil,
        authorName: String? = nil,
        authorImageUrl: String? = nil,
        ownerId: String? = nil,
        createdAt: Double? = nil,
        likes: Int? = nil,
        comments: Int? = nil,
        caption: String? = nil,
        source: String? = nil,
        url: String? = nil,
        productUrl: String? = nil,
        rec: Bool? = nil,
        reason: String? = nil,
        recipient: String? = nil,
        occasion: String? = nil,
        category: String? = nil,
        status: String? = nil,
        product: APIProduct? = nil,
        domain: String? = nil,
        merchant: String? = nil,
        price: Double? = nil,
        vibes: [String]? = nil,
        aspectRatio: Double? = nil,
        qualityScore: Double? = nil,
        contentType: String? = nil,
        mediaUrl: String? = nil,
        mediaUrls: [String]? = nil,
        posterUrl: String? = nil,
        music: UGCMusicTrack? = nil,
        recentComments: [Comment]? = nil,
        feedEligible: Bool? = nil,
        giftType: String? = nil,
        serviceDuration: String? = nil,
        story: String? = nil,
        productFeatures: [String]? = nil
    ) {
        self.postId = postId
        self.author = author
        self.authorName = authorName
        self.authorImageUrl = authorImageUrl
        self.ownerId = ownerId
        self.createdAt = createdAt
        self.likes = likes
        self.comments = comments
        self.caption = caption
        self.source = source
        self.url = url
        self.productUrl = productUrl
        self.rec = rec
        self.reason = reason
        self.recipient = recipient
        self.occasion = occasion
        self.category = category
        self.status = status
        self.product = product
        self.domain = domain
        self.merchant = merchant
        self.price = price
        self.vibes = vibes
        self.aspectRatio = aspectRatio
        self.qualityScore = qualityScore
        self.contentType = contentType
        self.mediaUrl = mediaUrl
        self.mediaUrls = mediaUrls
        self.posterUrl = posterUrl
        self.music = music
        self.recentComments = recentComments
        self.feedEligible = feedEligible
        self.giftType = giftType
        self.serviceDuration = serviceDuration
        self.story = story
        self.productFeatures = productFeatures
    }

}

public struct UGCPost: Identifiable, Codable, Hashable {
    public let postId: String
    public var ownerId: String? = nil
    public var authorName: String?
    public var authorImageUrl: String?
    public var caption: String
    public var likes: Int? = nil
    public var comments: Int? = nil
    public var mediaType: String
    public var mimeType: String?
    public var mediaUrl: String?
    public var mediaUrls: [String]? = nil
    public var posterUrl: String?
    public var music: UGCMusicTrack? = nil
    public var processingStatus: String
    public var productPipelineStatus: String? = nil
    public var moderationStatus: String
    public var moderationReason: [String]?
    public var recommendationLabels: [UGCLabel]?
    public var productLinks: [UGCProductLink]?
    public var createdAt: Double

    public var id: String { postId }
    public var isTerminal: Bool { ["READY", "REJECTED", "FAILED"].contains(processingStatus) }
}

public struct UGCProductLink: Identifiable, Codable, Hashable {
    public var name: String
    public var url: String
    public var id: String { url }
}

public struct UGCMusicTrack: Identifiable, Codable, Hashable {
    public var trackId: String
    public var title: String
    public var artist: String
    public var audioUrl: String
    public var durationSeconds: Int
    public var license: String
    public var licenseUrl: String?

    public var id: String { trackId }
}

public struct UGCMusicTracksResponse: Codable {
    public var items: [UGCMusicTrack]
}

public struct UGCUploadTarget: Codable {
    public var index: Int
    public var uploadUrl: String
    public var uploadHeaders: [String: String]
}

public struct UGCLabel: Codable, Hashable {
    public var name: String
    public var confidence: Double
}

public struct UGCUploadResponse: Codable {
    public var post: UGCPost
    public var uploadUrl: String
    public var uploadHeaders: [String: String]
    public var uploads: [UGCUploadTarget]? = nil
    public var posterUploadUrl: String?
    public var posterUploadHeaders: [String: String]?
    public var expiresIn: Int
}

public struct UGCPostsResponse: Codable {
    public var items: [UGCPost]
}

public struct UGCPostResponse: Codable {
    public var item: UGCPost
}

public struct UGCCompleteResponse: Codable {
    public var ok: Bool
    public var postId: String
    public var status: String?
}

public struct PostLikeResponse: Codable {
    public var liked: Bool
    public var likes: Int
}

public struct PostLikeStatesResponse: Codable {
    public var likedPostIds: [String]
}

public struct PostCommentsResponse: Codable {
    public var items: [Comment]
    public var count: Int
}

public struct PostCommentResponse: Codable {
    public var item: Comment
    public var count: Int
}

public struct AvatarUploadResponse: Codable {
    public var avatarId: String
    public var uploadUrl: String
    public var uploadHeaders: [String: String]
    public var expiresIn: Int
}

public struct AvatarCompleteResponse: Codable {
    public var ok: Bool
    public var imageUrl: String
}

public struct APIProduct: Codable {
    public var id: String?
    public var name: String?
    public var brand: String?
    public var price: Double?
    public var grad: String?
    public var emoji: String?
    public var image: String?
    // Product-page gallery written by infra/ingest/enrich-images.mjs.
    public var images: [String]?

    public init(
        id: String? = nil,
        name: String? = nil,
        brand: String? = nil,
        price: Double? = nil,
        grad: String? = nil,
        emoji: String? = nil,
        image: String? = nil,
        images: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.price = price
        self.grad = grad
        self.emoji = emoji
        self.image = image
        self.images = images
    }

}

public struct FeedResponse: Codable {
    public var items: [APIPost]?
    public var cursor: String?
}

public struct MixerMedia: Codable { public var url: String; public var role: String? }
public struct MixerOffer: Codable {
    public var offerId: String?; public var merchant: String?; public var url: String?
    public var price: Double?; public var currency: String?; public var availability: String?
}
public struct MixerCommerce: Codable { public var shoppability: String; public var offers: [MixerOffer]? }
public struct MixerTaxonomy: Codable { public var primaryCategoryId: String?; public var labelIds: [String]? }
public struct MixerCreator: Codable { public var id: String?; public var name: String? }
public struct MixerProvenance: Codable { public var type: String?; public var provider: String?; public var sourceUrl: String? }
public struct MixerQuality: Codable { public var score: Double?; public var giftable: Bool? }
public struct MixerCatalogItem: Codable {
    public var entityId: String; public var kind: String; public var title: String; public var summary: String?
    public var media: [MixerMedia]?; public var creator: MixerCreator?; public var provenance: MixerProvenance?
    public var taxonomy: MixerTaxonomy?; public var commerce: MixerCommerce; public var quality: MixerQuality?
    public var features: [String]?
    public var legacyPost: APIPost?
}
public struct MixerReason: Codable { public var code: String; public var label: String }
public struct MixerResult: Codable {
    public var item: MixerCatalogItem; public var rank: Int; public var reason: MixerReason
    public var attributionToken: String; public var source: String
}
public struct MixerResponse: Codable {
    public var recommendationId: String; public var surface: String; public var policyVersion: String
    public var modelVersion: String; public var taxonomyVersion: String; public var profileVersion: Int
    public var items: [MixerResult]; public var nextCursor: String?
}
public struct RemoteFeedTag: Codable { public var id: String; public var title: String; public var terms: [String]; public var maxPrice: Double? }
public struct RemoteFeedTheme: Codable { public var id: String; public var title: String; public var terms: [String]; public var tags: [RemoteFeedTag] }
public struct FeedTaxonomyResponse: Codable { public var version: String; public var themes: [RemoteFeedTheme] }

public struct RecipientLeaderboardItem: Identifiable {
    public let rank: Int
    public let voterCount: Int
    public let post: Post

    public init(
        rank: Int,
        voterCount: Int,
        post: Post
    ) {
        self.rank = rank
        self.voterCount = voterCount
        self.post = post
    }

    public var id: String { post.id }
}

public struct RecipientLeaderboardRow: Codable {
    public var rank: Int
    public var voterCount: Int
    public var item: MixerCatalogItem
}

public struct RecipientLeaderboardResponse: Codable {
    public var items: [RecipientLeaderboardRow]
}

public struct VectorItem: Identifiable, Codable {
    public var postId: String
    public var author: String?
    public var image: String?
    public var name: String?
    public var source: String?
    public var reason: String?
    public var url: String?
    public var productUrl: String?
    public var price: Double?
    public var merchant: String?
    public var domain: String?
    public var giftType: String?
    public var serviceDuration: String?

    public init(
        postId: String,
        author: String? = nil,
        image: String? = nil,
        name: String? = nil,
        source: String? = nil,
        reason: String? = nil,
        url: String? = nil,
        productUrl: String? = nil,
        price: Double? = nil,
        merchant: String? = nil,
        domain: String? = nil,
        giftType: String? = nil,
        serviceDuration: String? = nil
    ) {
        self.postId = postId
        self.author = author
        self.image = image
        self.name = name
        self.source = source
        self.reason = reason
        self.url = url
        self.productUrl = productUrl
        self.price = price
        self.merchant = merchant
        self.domain = domain
        self.giftType = giftType
        self.serviceDuration = serviceDuration
    }


    public var id: String { postId }
}

extension Post {
    /// A kNN neighbour rendered as a feed post. Shared by every surface that
    /// consumes /recommendations (Home picks, Ideas → For you, Maxi) so a
    /// vector pick looks identical wherever it lands.
    public init(vectorItem item: VectorItem) {
        self.init(
            id: item.postId,
            user: item.author ?? "giftmaxxing",
            time: "",
            product: Product(
                id: item.postId,
                name: item.name ?? "Gift idea",
                brand: item.merchant ?? item.source ?? "",
                price: item.price ?? 0,
                grad: .coral,
                emoji: "🎁",
                image: item.image
            ),
            caption: "",
            likes: 0,
            productUrl: item.productUrl ?? item.url,
            reason: item.reason ?? "Picked for you",
            domain: item.domain,
            giftType: item.giftType,
            serviceDuration: item.serviceDuration
        )
    }
}

// POST /packaging — a wrap plan for one recipient's pile, written by a vision
// model that has actually looked at the products, plus one rendered image of
// the result. `imageUrl` is nil when image generation is unavailable (model
// access, the cost breaker, or a render failure) — the plan still stands.
public struct PackagingPlanResponse: Codable {
    public var plan: PackagingPlan?
    public var imageUrl: String?
    public var cached: Bool?
}

public struct PackagingPlan: Codable {
    public var title: String?
    public var vibe: String?
    public var materials: [String]?
    public var steps: [String]?
    /// Hex strings, three of them — rendered as swatches.
    public var palette: [String]?
    /// A short handwritten-note suggestion the giver can adopt verbatim.
    public var noteIdea: String?
}

// int8-quantized vector as the server packs it (same scheme as GET /vectors).
public struct PackedVector: Codable {
    public var dim: Int
    public var scale: Float
    public var data: String // base64-encoded int8 components
}

public struct VectorResponse: Codable {
    public var items: [VectorItem]?
    public var source: String?
    // /visual-search echoes the query image's embedding so the client can keep
    // the photo as a taste seed instead of discarding it (research gap G3).
    public var queryVector: PackedVector?
}

public struct InteractionsResponse: Codable {
    public var items: [PersistedInteraction]?
}

// POST /challenges — the server builds and stores the deck; the app only
// needs the id to put in the share link (deck rides along for a preview).
public struct ChallengeCreateResponse: Codable {
    public var ok: Bool?
    public var challengeId: String
    public var deck: [ChallengeDeckItem]?

    public struct ChallengeDeckItem: Codable {
        public var postId: String
        public var name: String?
        public var image: String?
        public var price: Double?
        public var category: String?
        public var giftType: String?
        public var serviceDuration: String?
    }
}

// GET /challenges/{id} — public status. Group mode carries the shared tally:
// which cards the friends said yes to, and who has swiped so far.
public struct ChallengeStatusResponse: Codable {
    public var challengeId: String?
    public var inviterName: String?
    public var to: String?
    public var occasion: String?
    public var mode: String?
    public var responseCount: Int?
    public var deck: [ChallengeCreateResponse.ChallengeDeckItem]?
    public var groupPicks: [GroupPickItem]?
    public var responders: [String]?
    // mode == "verify": did they swipe right on the hidden pick? Aggregate
    // only — the per-card swipes stay sender-private on the server.
    public var verify: VerifySummary?
    // Sender-only (requires authenticating as the challenge's sender): every
    // guest response with per-card swipes. Powers the swipe-list "their
    // answers" view — a shared list's whole point is per-item yes/no.
    public var responses: [ChallengeResponseRow]?

    public struct ChallengeResponseRow: Codable {
        public var guestName: String?
        public var swipes: [ChallengeSwipe]?
        public var createdAt: Double?

        public struct ChallengeSwipe: Codable {
            public var id: String
            public var dir: String
        }
    }

    public struct VerifySummary: Codable {
        public var responses: Int?
        public var matched: Bool?
        public var by: String?
        public var label: String?
        public var score: Double?
    }

    public struct GroupPickItem: Codable, Identifiable {
        public var postId: String
        public var name: String?
        public var image: String?
        public var price: Double?
        public var category: String?
        public var yes: Int
        public var guests: [String]?

        public var id: String { postId }
    }
}

public struct ChallengeResponseAck: Codable {
    public var ok: Bool?
}

// GET /vectors — int8-quantized Titan embeddings for on-device similarity.
public struct VectorsResponse: Codable {
    public var items: [QuantizedVectorItem]?
    public var source: String?

    public init(
        items: [QuantizedVectorItem]? = nil,
        source: String? = nil
    ) {
        self.items = items
        self.source = source
    }


    public struct QuantizedVectorItem: Codable {
        public var key: String
        public var dim: Int?
        public var scale: Float
        public var data: String // base64-encoded int8 components
    }
}

public struct PersistedInteraction: Codable {
    public var targetId: String
    public var type: String
    public var createdAt: Double?
    public var data: InteractionData?

    public struct InteractionData: Codable {
        public var text: String?
    }
}

// GET /connections — soft profiles collected from shared swipe challenges.
public struct ConnectionsResponse: Codable {
    public var items: [SoftConnectionItem]?
    public var unseen: Int?
}

// How a challenge guest split their yesses between products and services —
// "they'd rather get a membership than a thing" (server verdict.giftTypeSplit).
public struct GiftTypeSplit: Codable {
    public var productYes: Int?
    public var productTotal: Int?
    public var serviceYes: Int?
    public var serviceTotal: Int?
    public var productYesRate: Double?
    public var serviceYesRate: Double?
}

public struct SoftConnectionItem: Codable, Identifiable {
    public var userId: String?
    public var connectionId: String
    public var soft: Bool?
    public var kind: String?
    public var guestName: String
    public var birthday: String?
    public var genderPref: String?
    public var vibes: [String]?
    public var seeds: [String]?
    public var negSeeds: [String]?
    public var giftTypeSplit: GiftTypeSplit?
    public var yesCount: Int?
    public var totalSwipes: Int?
    public var seen: Bool?
    public var createdAt: Double?

    public init(
        userId: String? = nil,
        connectionId: String,
        soft: Bool? = nil,
        kind: String? = nil,
        guestName: String,
        birthday: String? = nil,
        genderPref: String? = nil,
        vibes: [String]? = nil,
        seeds: [String]? = nil,
        negSeeds: [String]? = nil,
        giftTypeSplit: GiftTypeSplit? = nil,
        yesCount: Int? = nil,
        totalSwipes: Int? = nil,
        seen: Bool? = nil,
        createdAt: Double? = nil
    ) {
        self.userId = userId
        self.connectionId = connectionId
        self.soft = soft
        self.kind = kind
        self.guestName = guestName
        self.birthday = birthday
        self.genderPref = genderPref
        self.vibes = vibes
        self.seeds = seeds
        self.negSeeds = negSeeds
        self.giftTypeSplit = giftTypeSplit
        self.yesCount = yesCount
        self.totalSwipes = totalSwipes
        self.seen = seen
        self.createdAt = createdAt
    }


    public var id: String { connectionId }
}

public struct UserProfileResponse: Codable {
    public var item: UserProfile?
}

public struct UserProfile: Codable {
    public var userId: String?
    public var name: String?
    public var email: String?
    public var imageUrl: String?
    public var recipients: [Recipient]?
    public var events: [EventData]?
    // Onboarding markers written by the concierge (web or iOS). completedAt
    // present ⇒ this account has onboarded SOMEWHERE — don't re-gate it.
    public var completedAt: Double?
    public var interests: [String]?
    public var genderPref: String?
    public var visibility: String?
    // Per-account Gift Boards, synced so they survive sign-out / new devices.
    public var giftBoards: [SwipeList]?
    // The per-person cart, synced the same way (CartStore). PUT /me merges
    // patches, so boards and cart write independently without clobbering.
    public var cart: [CartSection]?
    // The public gifting persona (also served to friends via /people).
    public var tagline: String?
    public var philosophy: String?
    public var clothingSizes: [String: String]?
    public var dislikes: [String]?
    public var giftNote: String?
    public var giftShowcase: [GiftShowcaseItem]?

    public struct Recipient: Codable, Identifiable {
        public var id: String
        public var name: String
        public var relation: String
        public var sourceUser: String?
    }

    public struct EventData: Codable, Identifiable {
        public var id: String
        public var recipientId: String?
        public var type: String
        public var date: String?
        public var recurrence: String?
        public var reminderLeadDays: Int?
        public var budget: Double?
    }
}

public struct UpcomingEventsResponse: Codable {
    public var items: [UpcomingEvent]?
}

public struct UpcomingEvent: Identifiable, Codable {
    public var eventId: String?
    public var recipientId: String?
    public var type: String?
    public var title: String?
    // The server stores dates as "YYYY-MM-DD" strings (web/lib/events.ts
    // parity); older payloads used epoch millis. FlexibleDate decodes both —
    // a plain Double here made the whole items array throw on real data.
    public var date: FlexibleDate?
    public var recipientName: String?
    public var recurrence: String?
    public var reminderLeadDays: Int?
    public var budget: Double?
    public var daysUntil: Int?
    public var scope: String?
    public var recipient: EventRecipient?

    public var id: String { eventId ?? "\(recipientId ?? "")-\(type ?? "")-\(date?.dateValue?.timeIntervalSince1970 ?? 0)" }

    public struct EventRecipient: Codable {
        public var id: String
        public var name: String
        public var relation: String
        public var sourceUser: String?
    }
}

// Decodes a date that may arrive as "YYYY-MM-DD" or epoch milliseconds.
public struct FlexibleDate: Codable {
    public var dateValue: Date?

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let millis = try? container.decode(Double.self) {
            dateValue = Date(timeIntervalSince1970: millis / 1000)
        } else if let str = try? container.decode(String.self) {
            dateValue = FlexibleDate.parseYMD(str)
        } else {
            dateValue = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let dateValue {
            try container.encode(FlexibleDate.ymdString(from: dateValue))
        } else {
            try container.encodeNil()
        }
    }

    public static func parseYMD(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.date(from: str)
    }

    public static func ymdString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

// ── Circles (shared family/friend groups; web/lib/circles.ts parity) ─────────
// One EVENTS-table partition per circle: META + MEMBER# rows + EVT# rows.
// The share link is the credential — same trust model as invite links.
public struct CircleCreateResponse: Codable {
    public var ok: Bool?
    public var circleId: String
}

public struct CircleJoinResponse: Codable {
    public var ok: Bool?
    public var memberId: String?
    public var linkedUserId: String?
}

public struct ShoppableResponse: Codable {
    public var items: [VectorItem]?
    public var cached: Bool?
}

public struct BoardShareAck: Codable {
    public var ok: Bool?
    public var shareId: String?
}

public struct SharedBoard: Codable, Identifiable {
    public var shareId: String
    public var name: String
    public var recipientName: String?
    public var occasion: String?
    public var relationship: String?
    public var posts: [APIPost]?
    public var fromName: String?
    public var fromUserId: String?
    public var createdAt: Double?

    public var id: String { shareId }
}

public struct SharedBoardsResponse: Codable {
    public var items: [SharedBoard]?
}

public struct ChallengeInviteAck: Codable {
    public var ok: Bool?
    public var challengeId: String?
}

public struct ChallengeInvite: Codable, Identifiable {
    public var challengeId: String
    public var fromName: String?
    public var fromUserId: String?
    public var title: String?
    public var occasion: String?
    public var deckSize: Int?
    public var createdAt: Double?

    public var id: String { challengeId }
}

public struct ChallengeInvitesResponse: Codable {
    public var items: [ChallengeInvite]?
}

public struct CircleMemberAddResponse: Codable {
    public var ok: Bool?
    public var memberId: String?
    public var circleId: String?
}

public struct MyCircleRef: Codable, Identifiable {
    public var circleId: String
    public var name: String
    public var emoji: String?
    public var joinedAt: Double?

    public var id: String { circleId }
}

public struct MyCirclesResponse: Codable {
    public var items: [MyCircleRef]?
}

public struct CircleAck: Codable {
    public var ok: Bool?
    public var eventId: String?
}

public struct CircleDataResponse: Codable {
    public var circle: CircleMeta
    public var members: [CircleMember]?
    public var events: [CircleEvent]?

    public struct CircleMeta: Codable {
        public var circleId: String
        public var name: String
        public var emoji: String?
        public var createdAt: Double?
    }

    public struct CircleMember: Codable, Identifiable {
        public var memberId: String
        public var name: String
        public var birthday: String? // YYYY-MM-DD
        public var role: String?
        public var joinedAt: Double?
        /// Signed-in Giftmaxxing account linked to this seat (when claimed).
        public var linkedUserId: String?
        public var linkedHandle: String?
        public var linkedName: String?

        public var id: String { memberId }
    }

    public struct CircleEvent: Codable, Identifiable {
        public var eventId: String
        public var title: String
        public var date: String // YYYY-MM-DD
        public var type: String?
        public var forName: String?
        public var addedBy: String?
        public var createdAt: Double?

        public var id: String { eventId }
    }
}

// MARK: - Friends / people discovery / 1:1 DMs (web/lib/friends.ts parity)

public struct PublicPerson: Codable, Identifiable, Hashable {
    public var userId: String
    public var name: String
    public var handle: String
    public var bio: String?
    public var imageUrl: String?
    public var interests: [String]?
    public var materialisticCategories: [String]?
    public var style: String?
    public var role: String?
    public var visibility: String?
    // Gifting persona + the "gift me right" facts (sizes, dislikes, note,
    // photos of gifts they'd love) — what friends use to pick well.
    public var tagline: String?
    public var philosophy: String?
    public var clothingSizes: [String: String]?
    public var dislikes: [String]?
    public var giftNote: String?
    public var giftShowcase: [GiftShowcaseItem]?
    public var posts: [UGCPost]?
    public var friendCount: Int? = nil
    public var circles: [PersonCircle]? = nil

    public init(
        userId: String,
        name: String,
        handle: String,
        bio: String? = nil,
        imageUrl: String? = nil,
        interests: [String]? = nil,
        materialisticCategories: [String]? = nil,
        style: String? = nil,
        role: String? = nil,
        visibility: String? = nil,
        tagline: String? = nil,
        philosophy: String? = nil,
        clothingSizes: [String: String]? = nil,
        dislikes: [String]? = nil,
        giftNote: String? = nil,
        giftShowcase: [GiftShowcaseItem]? = nil,
        posts: [UGCPost]? = nil,
        friendCount: Int? = nil,
        circles: [PersonCircle]? = nil
    ) {
        self.userId = userId
        self.name = name
        self.handle = handle
        self.bio = bio
        self.imageUrl = imageUrl
        self.interests = interests
        self.materialisticCategories = materialisticCategories
        self.style = style
        self.role = role
        self.visibility = visibility
        self.tagline = tagline
        self.philosophy = philosophy
        self.clothingSizes = clothingSizes
        self.dislikes = dislikes
        self.giftNote = giftNote
        self.giftShowcase = giftShowcase
        self.posts = posts
        self.friendCount = friendCount
        self.circles = circles
    }


    public var id: String { userId }
}

public struct PersonCircle: Codable, Identifiable, Hashable {
    public var circleId: String
    public var name: String
    public var emoji: String?

    public var id: String { circleId }
}

// One photo in a profile's "gifts I'd love" showcase — a board item the
// owner wrote a why-note for, or explicitly liked.
public struct GiftShowcaseItem: Codable, Hashable, Identifiable {
    public var postId: String
    public var name: String?
    public var imageUrl: String?
    public var why: String?
    public var forWhom: String?
    public var brand: String?
    public var price: Double?
    public var productUrl: String?

    public init(
        postId: String,
        name: String? = nil,
        imageUrl: String? = nil,
        why: String? = nil,
        forWhom: String? = nil,
        brand: String? = nil,
        price: Double? = nil,
        productUrl: String? = nil
    ) {
        self.postId = postId
        self.name = name
        self.imageUrl = imageUrl
        self.why = why
        self.forWhom = forWhom
        self.brand = brand
        self.price = price
        self.productUrl = productUrl
    }


    public var id: String { postId }
}

public struct PeopleSearchResponse: Codable {
    public var items: [PublicPerson]?
}

public struct PersonResponse: Codable {
    public var item: PublicPerson?
}

public struct Friendship: Codable, Identifiable, Hashable {
    public var friendId: String
    public var status: String // pending | accepted
    public var requestedBy: String?
    public var incoming: Bool?
    public var circleId: String?
    public var createdAt: Double?
    public var updatedAt: Double?
    public var name: String?
    public var handle: String?
    public var bio: String?
    public var interests: [String]?
    public var imageUrl: String? = nil

    public init(
        friendId: String,
        status: String,
        requestedBy: String? = nil,
        incoming: Bool? = nil,
        circleId: String? = nil,
        createdAt: Double? = nil,
        updatedAt: Double? = nil,
        name: String? = nil,
        handle: String? = nil,
        bio: String? = nil,
        interests: [String]? = nil,
        imageUrl: String? = nil
    ) {
        self.friendId = friendId
        self.status = status
        self.requestedBy = requestedBy
        self.incoming = incoming
        self.circleId = circleId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.handle = handle
        self.bio = bio
        self.interests = interests
        self.imageUrl = imageUrl
    }




    public var id: String { friendId }

    public var isAccepted: Bool { status == "accepted" }
    public var isPending: Bool { status == "pending" }
}

public struct FriendsListResponse: Codable {
    public var items: [Friendship]?
}

public struct FriendshipStatusResponse: Codable {
    public var status: String // none | pending | accepted
    public var requestedBy: String?
    public var incoming: Bool?
}

public struct FriendActionResponse: Codable {
    public var ok: Bool?
    public var status: String?
    public var already: Bool?
}

public struct DmThread: Codable, Identifiable, Hashable {
    public var threadId: String
    public var otherUserId: String
    public var otherName: String?
    public var otherHandle: String?
    public var lastText: String?
    public var lastAt: Double?

    public init(
        threadId: String,
        otherUserId: String,
        otherName: String? = nil,
        otherHandle: String? = nil,
        lastText: String? = nil,
        lastAt: Double? = nil
    ) {
        self.threadId = threadId
        self.otherUserId = otherUserId
        self.otherName = otherName
        self.otherHandle = otherHandle
        self.lastText = lastText
        self.lastAt = lastAt
    }


    public var id: String { threadId }
}

public struct DmListResponse: Codable {
    public var items: [DmThread]?
}

public struct DmOpenResponse: Codable {
    public var ok: Bool?
    public var threadId: String?
}

public struct DmMessage: Codable, Identifiable, Hashable {
    public var id: String
    public var userId: String
    public var name: String
    public var text: String
    public var at: Double

    public init(
        id: String,
        userId: String,
        name: String,
        text: String,
        at: Double
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.text = text
        self.at = at
    }

}

public struct DmMessagesResponse: Codable {
    public var items: [DmMessage]?
}

public struct DmSendResponse: Codable {
    public var ok: Bool?
    public var message: DmMessage?
}

public struct CircleClaimResponse: Codable {
    public var ok: Bool?
    public var memberId: String?
    public var linkedUserId: String?
}

public struct DeltaSyncResponse: Codable {
    public var updatedPosts: [APIPost]?
    public var deletedPostIds: [String]?
    public var updatedEvents: [UpcomingEvent]?
    public var serverTime: Double?
}

public struct GraphResponse: Codable {
    public var nodes: [GraphNode]?
    public var edges: [GraphEdge]?
    public var counts: GraphCounts?

    public struct GraphCounts: Codable {
        public var nodes: Int
        public var edges: Int
    }
}

public struct GraphNode: Identifiable, Codable {
    public var id: String
    public var type: String
    public var scope: String?
    public var label: String?
}

public struct GraphEdge: Codable {
    public var rel: String
    public var from: String
    public var to: String
}
