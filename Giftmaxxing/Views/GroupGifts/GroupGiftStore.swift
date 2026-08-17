import Foundation
import GiftmaxxingCore

// Group gifting — the third swipe context: friends swipe the SAME server deck
// to converge on a gift for someone who never sees the link. The deck and every
// friend's picks live server-side under the challenge (mode="group"); this
// store keeps the creator's campaign list on-device, PoolsStore-style.
//
// Lifecycle: create (POST /challenges mode=group) → invite friends (link opens
// in their browser, no install) → everyone swipes → shared tally converges →
// pledge round (a Pool seeded with the winning card) → leaderboard of pledges.
struct GroupGift: Identifiable, Codable {
    let id: String              // the server challengeId
    var recipient: String
    var occasion: String?
    var inviterName: String
    var inviteURL: String
    var createdAt: Date
    var youSwiped: Bool
    // Set once the pledge round starts — links the campaign to its Pool.
    var poolId: String?
}

@MainActor
final class GroupGiftStore: ObservableObject {
    static let shared = GroupGiftStore()

    @Published private(set) var gifts: [GroupGift] = []

    private static let storageKey = "giftmaxxing_group_gifts"

    init() {
        load()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([GroupGift].self, from: data) {
            gifts = saved
        }
    }

    @discardableResult
    func add(
        challengeId: String,
        recipient: String,
        occasion: String?,
        inviterName: String,
        inviteURL: String
    ) -> GroupGift {
        let gift = GroupGift(
            id: challengeId,
            recipient: recipient.isEmpty ? "a friend" : recipient,
            occasion: occasion,
            inviterName: inviterName,
            inviteURL: inviteURL,
            createdAt: Date(),
            youSwiped: false,
            poolId: nil
        )
        gifts.insert(gift, at: 0)
        persist()
        AnalyticsEngine.shared.trackScreenView(screen: "group_gift_created")
        return gift
    }

    // Account boundary (AccountLocalState): campaigns are private.
    func clear() {
        gifts = []
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    func markSwiped(_ id: String) {
        guard let idx = gifts.firstIndex(where: { $0.id == id }) else { return }
        gifts[idx].youSwiped = true
        persist()
    }

    func attachPool(_ poolId: String, to id: String) {
        guard let idx = gifts.firstIndex(where: { $0.id == id }) else { return }
        gifts[idx].poolId = poolId
        persist()
    }

    func remove(_ id: String) {
        gifts.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(gifts) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
