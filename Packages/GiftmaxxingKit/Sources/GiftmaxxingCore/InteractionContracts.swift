import Foundation

// The contract between the ranking stack and whatever uploads its signals.
//
// It lives in Core, not in GiftmaxxingRecommendation, so GiftmaxxingNetworking
// can conform to it without importing the ranking module — networking should
// never depend on ranking.

// IMPORTANT: if nothing sets InteractionQueue's uploader, interactions queue
// forever and every taste signal is silently lost — no crash, no failing test.
// InteractionQueue.flush() asserts in debug as the tripwire for exactly that.
public protocol InteractionUploading: AnyObject, Sendable {
    func sendInteractionsBatch(_ batch: [PendingInteraction]) async throws
    func submitMixerEvents(_ events: [[String: Any]], anonymousId: String?) async throws
}

public struct PendingInteraction: Codable {
    public let userId: String
    public let targetId: String
    public let type: String
    public let queuedAt: Double
    // Optional context ({mode:"gift", giftType, decisionMs, amount…}) —
    // rides to POST /interactions as `data` so gift-mode events can build
    // per-recipient taste server-side. Optional: old queued files decode.
    public var data: [String: String]?
    public var recommendationId: String?
    public var attributionToken: String?
    public var position: Int?
    public var dwellMs: Double?
    public var forceMixer: Bool?

    public init(
        userId: String,
        targetId: String,
        type: String,
        queuedAt: Double,
        data: [String: String]? = nil,
        recommendationId: String? = nil,
        attributionToken: String? = nil,
        position: Int? = nil,
        dwellMs: Double? = nil,
        forceMixer: Bool? = nil
    ) {
        self.userId = userId
        self.targetId = targetId
        self.type = type
        self.queuedAt = queuedAt
        self.data = data
        self.recommendationId = recommendationId
        self.attributionToken = attributionToken
        self.position = position
        self.dwellMs = dwellMs
        self.forceMixer = forceMixer
    }

}
