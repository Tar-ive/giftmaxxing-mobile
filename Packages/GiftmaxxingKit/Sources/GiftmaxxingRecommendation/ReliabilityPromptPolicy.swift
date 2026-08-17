import Foundation
import GiftmaxxingCore

public struct ReliabilityPromptPolicy {
    public static let minimumCompletedSwipes = 5
    public static let cooldown: TimeInterval = 2 * 24 * 60 * 60

    public static func canPrompt(
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
