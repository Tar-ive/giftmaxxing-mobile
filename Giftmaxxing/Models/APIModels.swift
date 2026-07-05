import Foundation

struct APIPost: Codable {
    let postId: String
    var author: String?
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
    var qualityScore: Double?
    var contentType: String?
    var feedEligible: Bool?
}

struct APIProduct: Codable {
    var id: String?
    var name: String?
    var brand: String?
    var price: Double?
    var grad: String?
    var emoji: String?
    var image: String?
}

struct FeedResponse: Codable {
    var items: [APIPost]?
    var cursor: String?
}

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

    var id: String { postId }
}

struct VectorResponse: Codable {
    var items: [VectorItem]?
    var source: String?
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
    var date: Double?
    var recipientName: String?
    var recurrence: String?
    var reminderLeadDays: Int?
    var budget: Double?
    var daysUntil: Int?
    var scope: String?
    var recipient: EventRecipient?

    var id: String { eventId ?? "\(recipientId ?? "")-\(type ?? "")-\(date ?? 0)" }

    struct EventRecipient: Codable {
        var id: String
        var name: String
        var relation: String
        var sourceUser: String?
    }
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
