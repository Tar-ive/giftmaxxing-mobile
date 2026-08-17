import Foundation
import GiftmaxxingCore

// Event schema modeled after Instagram's impression tracking + Tinder's swipe
// telemetry. Each event captures what happened, how long it took, and the
// behavioral context (velocity, hesitation, scroll depth) that feeds the
// recommendation engine.
//
// Apple APIs used:
//   - CFAbsoluteTimeGetCurrent() for sub-ms timestamps
//   - ProcessInfo.processInfo.thermalState for battery/thermal context
//   - UIApplication lifecycle notifications for session tracking
//   - UIPanGestureRecognizer.velocity(in:) for swipe velocity
//   - GeometryReader + onAppear/onDisappear for viewport-based dwell time

struct AnalyticsEvent: Codable, Identifiable {
    let id: String
    let type: EventType
    let timestamp: Double
    var properties: [String: AnyCodableValue]

    init(type: EventType, properties: [String: AnyCodableValue] = [:]) {
        self.id = UUID().uuidString
        self.type = type
        self.timestamp = Date().timeIntervalSince1970 * 1000
        self.properties = properties
    }

    enum EventType: String, Codable {
        // Session lifecycle (Instagram-style)
        case sessionStart = "session_start"
        case sessionEnd = "session_end"
        case sessionResume = "session_resume"
        case sessionBackground = "session_background"

        // Feed engagement (Instagram-style)
        case feedImpression = "feed_impression"
        case feedDwell = "feed_dwell"
        case feedScroll = "feed_scroll"
        case feedScrollDepth = "feed_scroll_depth"
        case feedRevisit = "feed_revisit"

        // Content interaction
        case contentLike = "content_like"
        case contentUnlike = "content_unlike"
        case contentSave = "content_save"
        case contentUnsave = "content_unsave"
        case contentShare = "content_share"
        case contentTap = "content_tap"
        case contentComment = "content_comment"
        // User typed words for a specific gift (why-note / gift letter) — the
        // P_Custom label of the MTL value model (infra/ml). Joined server-side
        // by (userId, postId), so postId context is required.
        case customMessage = "custom_message"

        // Swipe deck (Tinder-style)
        case swipeCardShown = "swipe_card_shown"
        case swipeRight = "swipe_right"
        case swipeLeft = "swipe_left"
        case swipeDecisionTime = "swipe_decision_time"
        case swipeVelocity = "swipe_velocity"
        case swipeHesitation = "swipe_hesitation"
        case swipeDeckComplete = "swipe_deck_complete"
        case challengeAbandoned = "challenge_abandoned"
        case swipeUndo = "swipe_undo"
        case productReliabilityVote = "product_reliability_vote"

        // Maxi AI
        case maxiConversationStart = "maxi_conversation_start"
        case maxiMessageSent = "maxi_message_sent"
        case maxiResponseReceived = "maxi_response_received"
        case maxiProductTap = "maxi_product_tap"
        // Thumbs up/down on a set of Maxi picks — a label on what the ranker
        // actually served, and the only signal that says the ANSWER missed
        // rather than one item missing.
        case maxiRating = "maxi_rating"

        // Navigation
        case tabSwitch = "tab_switch"
        case screenView = "screen_view"

        // Product funnel
        case productView = "product_view"
        case productAffiliateClick = "product_affiliate_click"

        // Search
        case searchQuery = "search_query"
        case searchResultTap = "search_result_tap"
    }
}

// Type-erased Codable wrapper for heterogeneous property values
enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        throw DecodingError.typeMismatch(AnyCodableValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        }
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }
}
