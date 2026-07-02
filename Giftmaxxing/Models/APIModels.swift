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

struct PersistedInteraction: Codable {
    var targetId: String
    var type: String
    var createdAt: Double?
    var data: InteractionData?

    struct InteractionData: Codable {
        var text: String?
    }
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
