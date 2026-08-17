import Foundation
import GiftmaxxingCore

// The Maxi transcript, persisted per account.
//
// Maxi's whole value is continuity — it remembers who you shop for, what you
// said your budget was, which of the three picks you liked. Until now the
// transcript lived inside MaxiViewModel and died with the sheet, so every
// re-open restarted the interview. This store keeps it across dismissals and
// launches while staying local-only: the server already holds durable facts
// (GRAPH `MEM#` rows written by remember_fact), so the transcript is a UI
// convenience, not a second source of truth.
//
// Privacy: a transcript names the recipients you shop for, so it is wiped by
// AccountLocalState.clearPrivateStores() on sign-out and account switch —
// never visible to the next account on the same device.
@MainActor
final class MaxiConversationStore: ObservableObject {
    static let shared = MaxiConversationStore()

    private static let storageKey = "giftmaxxing_maxi_conversation"
    // Deep enough to hold a full gifting session; the wire history is capped at
    // 12 turns server-side anyway (handler.mjs buildMaxiMessages).
    private static let maxMessages = 60

    @Published private(set) var messages: [MaxiMessage] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([MaxiMessage].self, from: data) {
            messages = saved
        }
    }

    var isEmpty: Bool { messages.isEmpty }

    func append(_ message: MaxiMessage) {
        messages.append(message)
        if messages.count > Self.maxMessages {
            messages.removeFirst(messages.count - Self.maxMessages)
        }
        persist()
    }

    /// Adopt a transcript restored from the server (new device / reinstall).
    func replaceAll(_ restored: [MaxiMessage]) {
        messages = Array(restored.suffix(Self.maxMessages))
        persist()
    }

    /// Record a thumbs up/down on a specific reply.
    func rate(messageId: String, rating: Int) {
        guard let i = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[i].rating = rating
        persist()
    }

    /// Replace the last message — used when a streamed/retried reply supersedes
    /// a placeholder.
    func replaceLast(with message: MaxiMessage) {
        guard !messages.isEmpty else { return append(message) }
        messages[messages.count - 1] = message
        persist()
    }

    /// The alternating (role, text) history the /maxi route expects, excluding
    /// the turn currently being sent.
    func history(excludingLast: Bool = true) -> [(role: String, text: String)] {
        let source = excludingLast ? messages.dropLast() : messages[...]
        return source.map { (role: $0.role.rawValue, text: $0.text) }
    }

    /// New conversation, same account ("Start over" in the chat).
    func reset() {
        messages = []
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    /// Account boundary — see AccountLocalState.clearPrivateStores().
    func clear() { reset() }

    private func persist() {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
