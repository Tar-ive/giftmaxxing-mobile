import Foundation

struct APIPost: Codable {
    let postId: String
    var author: String?
    var authorName: String?
    var authorImageUrl: String?
    var ownerId: String?
    var createdAt: Double?
    var likes: Int?
    var comments: Int?
    var caption: String?
    var source: String?
    var url: String?
    var productUrl: String?
    var rec: Bool?
    var reason: String?
    var recipient: String?
    var occasion: String?
    var category: String?
    var status: String?
    var product: APIProduct?
    // Serve-time enrichment attached by the backend feed/recommendation routes
    // (classifyPin output + raw commerce fields) — used by the on-device ranker.
    var domain: String?
    var merchant: String?
    var price: Double?
    var vibes: [String]?
    let aspectRatio: Double?
    var qualityScore: Double?
    var contentType: String?
    var mediaUrl: String?
    var mediaUrls: [String]?
    var posterUrl: String?
    var music: UGCMusicTrack?
    var recentComments: [Comment]? = nil
    var feedEligible: Bool?
    // Products vs gift-able services (a year of Netflix, a Costco membership…).
    var giftType: String?
    var serviceDuration: String?
    // Maker's note / anecdote / craftsmanship detail (Shopify ingests carry
    // the product description; long-press on the feed image reveals it).
    var story: String?
}

struct UGCPost: Identifiable, Codable, Hashable {
    let postId: String
    var ownerId: String? = nil
    var authorName: String?
    var authorImageUrl: String?
    var caption: String
    var likes: Int? = nil
    var comments: Int? = nil
    var mediaType: String
    var mimeType: String?
    var mediaUrl: String?
    var mediaUrls: [String]? = nil
    var posterUrl: String?
    var music: UGCMusicTrack? = nil
    var processingStatus: String
    var moderationStatus: String
    var moderationReason: [String]?
    var recommendationLabels: [UGCLabel]?
    var createdAt: Double

    var id: String { postId }
    var isTerminal: Bool { ["READY", "REJECTED", "FAILED"].contains(processingStatus) }
}

struct UGCMusicTrack: Identifiable, Codable, Hashable {
    var trackId: String
    var title: String
    var artist: String
    var audioUrl: String
    var durationSeconds: Int
    var license: String
    var licenseUrl: String?

    var id: String { trackId }
}

struct UGCMusicTracksResponse: Codable {
    var items: [UGCMusicTrack]
}

struct UGCUploadTarget: Codable {
    var index: Int
    var uploadUrl: String
    var uploadHeaders: [String: String]
}

struct UGCLabel: Codable, Hashable {
    var name: String
    var confidence: Double
}

struct UGCUploadResponse: Codable {
    var post: UGCPost
    var uploadUrl: String
    var uploadHeaders: [String: String]
    var uploads: [UGCUploadTarget]? = nil
    var posterUploadUrl: String?
    var posterUploadHeaders: [String: String]?
    var expiresIn: Int
}

struct UGCPostsResponse: Codable {
    var items: [UGCPost]
}

struct UGCPostResponse: Codable {
    var item: UGCPost
}

struct UGCCompleteResponse: Codable {
    var ok: Bool
    var postId: String
    var status: String?
}

struct PostLikeResponse: Codable {
    var liked: Bool
    var likes: Int
}

struct PostLikeStatesResponse: Codable {
    var likedPostIds: [String]
}

struct PostCommentsResponse: Codable {
    var items: [Comment]
    var count: Int
}

struct PostCommentResponse: Codable {
    var item: Comment
    var count: Int
}

struct AvatarUploadResponse: Codable {
    var avatarId: String
    var uploadUrl: String
    var uploadHeaders: [String: String]
    var expiresIn: Int
}

struct AvatarCompleteResponse: Codable {
    var ok: Bool
    var imageUrl: String
}

struct APIProduct: Codable {
    var id: String?
    var name: String?
    var brand: String?
    var price: Double?
    var grad: String?
    var emoji: String?
    var image: String?
    // Product-page gallery written by infra/ingest/enrich-images.mjs.
    var images: [String]?
}

struct FeedResponse: Codable {
    var items: [APIPost]?
    var cursor: String?
}

struct MixerMedia: Codable { var url: String; var role: String? }
struct MixerOffer: Codable {
    var offerId: String?; var merchant: String?; var url: String?
    var price: Double?; var currency: String?; var availability: String?
}
struct MixerCommerce: Codable { var shoppability: String; var offers: [MixerOffer]? }
struct MixerTaxonomy: Codable { var primaryCategoryId: String?; var labelIds: [String]? }
struct MixerCreator: Codable { var id: String?; var name: String? }
struct MixerProvenance: Codable { var type: String?; var provider: String?; var sourceUrl: String? }
struct MixerQuality: Codable { var score: Double?; var giftable: Bool? }
struct MixerCatalogItem: Codable {
    var entityId: String; var kind: String; var title: String; var summary: String?
    var media: [MixerMedia]?; var creator: MixerCreator?; var provenance: MixerProvenance?
    var taxonomy: MixerTaxonomy?; var commerce: MixerCommerce; var quality: MixerQuality?
    var legacyPost: APIPost?
}
struct MixerReason: Codable { var code: String; var label: String }
struct MixerResult: Codable {
    var item: MixerCatalogItem; var rank: Int; var reason: MixerReason
    var attributionToken: String; var source: String
}
struct MixerResponse: Codable {
    var recommendationId: String; var surface: String; var policyVersion: String
    var modelVersion: String; var taxonomyVersion: String; var profileVersion: Int
    var items: [MixerResult]; var nextCursor: String?
}
struct RemoteFeedTag: Codable { var id: String; var title: String; var terms: [String]; var maxPrice: Double? }
struct RemoteFeedTheme: Codable { var id: String; var title: String; var terms: [String]; var tags: [RemoteFeedTag] }
struct FeedTaxonomyResponse: Codable { var version: String; var themes: [RemoteFeedTheme] }

struct VectorItem: Identifiable, Codable {
    var postId: String
    var author: String?
    var image: String?
    var name: String?
    var source: String?
    var reason: String?
    var url: String?
    var productUrl: String?
    var price: Double?
    var merchant: String?
    var domain: String?
    var giftType: String?
    var serviceDuration: String?

    var id: String { postId }
}

extension Post {
    /// A kNN neighbour rendered as a feed post. Shared by every surface that
    /// consumes /recommendations (Home picks, Ideas → For you, Maxi) so a
    /// vector pick looks identical wherever it lands.
    init(vectorItem item: VectorItem) {
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
struct PackagingPlanResponse: Codable {
    var plan: PackagingPlan?
    var imageUrl: String?
    var cached: Bool?
}

struct PackagingPlan: Codable {
    var title: String?
    var vibe: String?
    var materials: [String]?
    var steps: [String]?
    /// Hex strings, three of them — rendered as swatches.
    var palette: [String]?
    /// A short handwritten-note suggestion the giver can adopt verbatim.
    var noteIdea: String?
}

// int8-quantized vector as the server packs it (same scheme as GET /vectors).
struct PackedVector: Codable {
    var dim: Int
    var scale: Float
    var data: String // base64-encoded int8 components
}

struct VectorResponse: Codable {
    var items: [VectorItem]?
    var source: String?
    // /visual-search echoes the query image's embedding so the client can keep
    // the photo as a taste seed instead of discarding it (research gap G3).
    var queryVector: PackedVector?
}

struct InteractionsResponse: Codable {
    var items: [PersistedInteraction]?
}

// POST /challenges — the server builds and stores the deck; the app only
// needs the id to put in the share link (deck rides along for a preview).
struct ChallengeCreateResponse: Codable {
    var ok: Bool?
    var challengeId: String
    var deck: [ChallengeDeckItem]?

    struct ChallengeDeckItem: Codable {
        var postId: String
        var name: String?
        var image: String?
        var price: Double?
        var category: String?
        var giftType: String?
        var serviceDuration: String?
    }
}

// GET /challenges/{id} — public status. Group mode carries the shared tally:
// which cards the friends said yes to, and who has swiped so far.
struct ChallengeStatusResponse: Codable {
    var challengeId: String?
    var inviterName: String?
    var to: String?
    var occasion: String?
    var mode: String?
    var responseCount: Int?
    var deck: [ChallengeCreateResponse.ChallengeDeckItem]?
    var groupPicks: [GroupPickItem]?
    var responders: [String]?
    // mode == "verify": did they swipe right on the hidden pick? Aggregate
    // only — the per-card swipes stay sender-private on the server.
    var verify: VerifySummary?
    // Sender-only (requires authenticating as the challenge's sender): every
    // guest response with per-card swipes. Powers the swipe-list "their
    // answers" view — a shared list's whole point is per-item yes/no.
    var responses: [ChallengeResponseRow]?

    struct ChallengeResponseRow: Codable {
        var guestName: String?
        var swipes: [ChallengeSwipe]?
        var createdAt: Double?

        struct ChallengeSwipe: Codable {
            var id: String
            var dir: String
        }
    }

    struct VerifySummary: Codable {
        var responses: Int?
        var matched: Bool?
        var by: String?
        var label: String?
        var score: Double?
    }

    struct GroupPickItem: Codable, Identifiable {
        var postId: String
        var name: String?
        var image: String?
        var price: Double?
        var category: String?
        var yes: Int
        var guests: [String]?

        var id: String { postId }
    }
}

struct ChallengeResponseAck: Codable {
    var ok: Bool?
}

// GET /vectors — int8-quantized Titan embeddings for on-device similarity.
struct VectorsResponse: Codable {
    var items: [QuantizedVectorItem]?
    var source: String?

    struct QuantizedVectorItem: Codable {
        var key: String
        var dim: Int?
        var scale: Float
        var data: String // base64-encoded int8 components
    }
}

struct PersistedInteraction: Codable {
    var targetId: String
    var type: String
    var createdAt: Double?
    var data: InteractionData?

    struct InteractionData: Codable {
        var text: String?
    }
}

// GET /connections — soft profiles collected from shared swipe challenges.
struct ConnectionsResponse: Codable {
    var items: [SoftConnectionItem]?
    var unseen: Int?
}

// How a challenge guest split their yesses between products and services —
// "they'd rather get a membership than a thing" (server verdict.giftTypeSplit).
struct GiftTypeSplit: Codable {
    var productYes: Int?
    var productTotal: Int?
    var serviceYes: Int?
    var serviceTotal: Int?
    var productYesRate: Double?
    var serviceYesRate: Double?
}

struct SoftConnectionItem: Codable, Identifiable {
    var userId: String?
    var connectionId: String
    var soft: Bool?
    var kind: String?
    var guestName: String
    var birthday: String?
    var genderPref: String?
    var vibes: [String]?
    var seeds: [String]?
    var negSeeds: [String]?
    var giftTypeSplit: GiftTypeSplit?
    var yesCount: Int?
    var totalSwipes: Int?
    var seen: Bool?
    var createdAt: Double?

    var id: String { connectionId }
}

struct UserProfileResponse: Codable {
    var item: UserProfile?
}

struct UserProfile: Codable {
    var userId: String?
    var name: String?
    var email: String?
    var imageUrl: String?
    var recipients: [Recipient]?
    var events: [EventData]?
    // Onboarding markers written by the concierge (web or iOS). completedAt
    // present ⇒ this account has onboarded SOMEWHERE — don't re-gate it.
    var completedAt: Double?
    var interests: [String]?
    var genderPref: String?
    var visibility: String?
    // Per-account Gift Boards, synced so they survive sign-out / new devices.
    var giftBoards: [SwipeList]?
    // The per-person cart, synced the same way (CartStore). PUT /me merges
    // patches, so boards and cart write independently without clobbering.
    var cart: [CartSection]?
    // The public gifting persona (also served to friends via /people).
    var tagline: String?
    var philosophy: String?
    var clothingSizes: [String: String]?
    var dislikes: [String]?
    var giftNote: String?
    var giftShowcase: [GiftShowcaseItem]?

    struct Recipient: Codable, Identifiable {
        var id: String
        var name: String
        var relation: String
        var sourceUser: String?
    }

    struct EventData: Codable, Identifiable {
        var id: String
        var recipientId: String?
        var type: String
        var date: String?
        var recurrence: String?
        var reminderLeadDays: Int?
        var budget: Double?
    }
}

struct UpcomingEventsResponse: Codable {
    var items: [UpcomingEvent]?
}

struct UpcomingEvent: Identifiable, Codable {
    var eventId: String?
    var recipientId: String?
    var type: String?
    var title: String?
    // The server stores dates as "YYYY-MM-DD" strings (web/lib/events.ts
    // parity); older payloads used epoch millis. FlexibleDate decodes both —
    // a plain Double here made the whole items array throw on real data.
    var date: FlexibleDate?
    var recipientName: String?
    var recurrence: String?
    var reminderLeadDays: Int?
    var budget: Double?
    var daysUntil: Int?
    var scope: String?
    var recipient: EventRecipient?

    var id: String { eventId ?? "\(recipientId ?? "")-\(type ?? "")-\(date?.dateValue?.timeIntervalSince1970 ?? 0)" }

    struct EventRecipient: Codable {
        var id: String
        var name: String
        var relation: String
        var sourceUser: String?
    }
}

// Decodes a date that may arrive as "YYYY-MM-DD" or epoch milliseconds.
struct FlexibleDate: Codable {
    var dateValue: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let millis = try? container.decode(Double.self) {
            dateValue = Date(timeIntervalSince1970: millis / 1000)
        } else if let str = try? container.decode(String.self) {
            dateValue = FlexibleDate.parseYMD(str)
        } else {
            dateValue = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let dateValue {
            try container.encode(FlexibleDate.ymdString(from: dateValue))
        } else {
            try container.encodeNil()
        }
    }

    static func parseYMD(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.date(from: str)
    }

    static func ymdString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

// ── Circles (shared family/friend groups; web/lib/circles.ts parity) ─────────
// One EVENTS-table partition per circle: META + MEMBER# rows + EVT# rows.
// The share link is the credential — same trust model as invite links.
struct CircleCreateResponse: Codable {
    var ok: Bool?
    var circleId: String
}

struct CircleJoinResponse: Codable {
    var ok: Bool?
    var memberId: String?
    var linkedUserId: String?
}

struct ShoppableResponse: Codable {
    var items: [VectorItem]?
    var cached: Bool?
}

struct BoardShareAck: Codable {
    var ok: Bool?
    var shareId: String?
}

struct SharedBoard: Codable, Identifiable {
    var shareId: String
    var name: String
    var recipientName: String?
    var occasion: String?
    var relationship: String?
    var posts: [APIPost]?
    var fromName: String?
    var fromUserId: String?
    var createdAt: Double?

    var id: String { shareId }
}

struct SharedBoardsResponse: Codable {
    var items: [SharedBoard]?
}

struct ChallengeInviteAck: Codable {
    var ok: Bool?
    var challengeId: String?
}

struct ChallengeInvite: Codable, Identifiable {
    var challengeId: String
    var fromName: String?
    var fromUserId: String?
    var title: String?
    var occasion: String?
    var deckSize: Int?
    var createdAt: Double?

    var id: String { challengeId }
}

struct ChallengeInvitesResponse: Codable {
    var items: [ChallengeInvite]?
}

struct CircleMemberAddResponse: Codable {
    var ok: Bool?
    var memberId: String?
    var circleId: String?
}

struct MyCircleRef: Codable, Identifiable {
    var circleId: String
    var name: String
    var emoji: String?
    var joinedAt: Double?

    var id: String { circleId }
}

struct MyCirclesResponse: Codable {
    var items: [MyCircleRef]?
}

struct CircleAck: Codable {
    var ok: Bool?
    var eventId: String?
}

struct CircleDataResponse: Codable {
    var circle: CircleMeta
    var members: [CircleMember]?
    var events: [CircleEvent]?

    struct CircleMeta: Codable {
        var circleId: String
        var name: String
        var emoji: String?
        var createdAt: Double?
    }

    struct CircleMember: Codable, Identifiable {
        var memberId: String
        var name: String
        var birthday: String? // YYYY-MM-DD
        var role: String?
        var joinedAt: Double?
        /// Signed-in Giftmaxxing account linked to this seat (when claimed).
        var linkedUserId: String?
        var linkedHandle: String?
        var linkedName: String?

        var id: String { memberId }
    }

    struct CircleEvent: Codable, Identifiable {
        var eventId: String
        var title: String
        var date: String // YYYY-MM-DD
        var type: String?
        var forName: String?
        var addedBy: String?
        var createdAt: Double?

        var id: String { eventId }
    }
}

// MARK: - Friends / people discovery / 1:1 DMs (web/lib/friends.ts parity)

struct PublicPerson: Codable, Identifiable, Hashable {
    var userId: String
    var name: String
    var handle: String
    var bio: String?
    var imageUrl: String?
    var interests: [String]?
    var materialisticCategories: [String]?
    var style: String?
    var role: String?
    var visibility: String?
    // Gifting persona + the "gift me right" facts (sizes, dislikes, note,
    // photos of gifts they'd love) — what friends use to pick well.
    var tagline: String?
    var philosophy: String?
    var clothingSizes: [String: String]?
    var dislikes: [String]?
    var giftNote: String?
    var giftShowcase: [GiftShowcaseItem]?
    var posts: [UGCPost]?
    var friendCount: Int? = nil
    var circles: [PersonCircle]? = nil

    var id: String { userId }
}

struct PersonCircle: Codable, Identifiable, Hashable {
    var circleId: String
    var name: String
    var emoji: String?

    var id: String { circleId }
}

// One photo in a profile's "gifts I'd love" showcase — a board item the
// owner wrote a why-note for, or explicitly liked.
struct GiftShowcaseItem: Codable, Hashable, Identifiable {
    var postId: String
    var name: String?
    var imageUrl: String?
    var why: String?
    var forWhom: String?
    var brand: String?
    var price: Double?
    var productUrl: String?

    var id: String { postId }
}

struct PeopleSearchResponse: Codable {
    var items: [PublicPerson]?
}

struct PersonResponse: Codable {
    var item: PublicPerson?
}

struct Friendship: Codable, Identifiable, Hashable {
    var friendId: String
    var status: String // pending | accepted
    var requestedBy: String?
    var incoming: Bool?
    var circleId: String?
    var createdAt: Double?
    var updatedAt: Double?
    var name: String?
    var handle: String?
    var bio: String?
    var interests: [String]?
    var imageUrl: String? = nil

    var id: String { friendId }

    var isAccepted: Bool { status == "accepted" }
    var isPending: Bool { status == "pending" }
}

struct FriendsListResponse: Codable {
    var items: [Friendship]?
}

struct FriendshipStatusResponse: Codable {
    var status: String // none | pending | accepted
    var requestedBy: String?
    var incoming: Bool?
}

struct FriendActionResponse: Codable {
    var ok: Bool?
    var status: String?
    var already: Bool?
}

struct DmThread: Codable, Identifiable, Hashable {
    var threadId: String
    var otherUserId: String
    var otherName: String?
    var otherHandle: String?
    var lastText: String?
    var lastAt: Double?

    var id: String { threadId }
}

struct DmListResponse: Codable {
    var items: [DmThread]?
}

struct DmOpenResponse: Codable {
    var ok: Bool?
    var threadId: String?
}

struct DmMessage: Codable, Identifiable, Hashable {
    var id: String
    var userId: String
    var name: String
    var text: String
    var at: Double
}

struct DmMessagesResponse: Codable {
    var items: [DmMessage]?
}

struct DmSendResponse: Codable {
    var ok: Bool?
    var message: DmMessage?
}

struct CircleClaimResponse: Codable {
    var ok: Bool?
    var memberId: String?
    var linkedUserId: String?
}

struct DeltaSyncResponse: Codable {
    var updatedPosts: [APIPost]?
    var deletedPostIds: [String]?
    var updatedEvents: [UpcomingEvent]?
    var serverTime: Double?
}

struct GraphResponse: Codable {
    var nodes: [GraphNode]?
    var edges: [GraphEdge]?
    var counts: GraphCounts?

    struct GraphCounts: Codable {
        var nodes: Int
        var edges: Int
    }
}

struct GraphNode: Identifiable, Codable {
    var id: String
    var type: String
    var scope: String?
    var label: String?
}

struct GraphEdge: Codable {
    var rel: String
    var from: String
    var to: String
}
