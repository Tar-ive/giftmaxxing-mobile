import Foundation

struct ReliabilityPromptPolicy {
    static let minimumCompletedSwipes = 5
    static let cooldown: TimeInterval = 2 * 24 * 60 * 60

    static func canPrompt(
        completedSwipes: Int,
        lastPromptAt: Date?,
        hasVote: Bool,
        now: Date = Date()
    ) -> Bool {
        guard completedSwipes >= minimumCompletedSwipes, !hasVote else { return false }
        guard let lastPromptAt else { return true }
        return now.timeIntervalSince(lastPromptAt) >= cooldown
    }
}
