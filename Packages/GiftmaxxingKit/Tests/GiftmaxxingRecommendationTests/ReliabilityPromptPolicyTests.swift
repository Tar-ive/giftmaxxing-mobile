import XCTest
@testable import GiftmaxxingRecommendation
import GiftmaxxingCore

final class ReliabilityPromptPolicyTests: XCTestCase {
    func testWaitsForFiveCompletedSwipes() {
        XCTAssertFalse(ReliabilityPromptPolicy.canPrompt(
            completedSwipes: 4, lastPromptAt: nil, hasVote: false
        ))
        XCTAssertTrue(ReliabilityPromptPolicy.canPrompt(
            completedSwipes: 5, lastPromptAt: nil, hasVote: false
        ))
    }

    func testTwoDayCooldownIsPerPrompt() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(ReliabilityPromptPolicy.canPrompt(
            completedSwipes: 20,
            lastPromptAt: now.addingTimeInterval(-ReliabilityPromptPolicy.cooldown + 1),
            hasVote: false,
            now: now
        ))
        XCTAssertTrue(ReliabilityPromptPolicy.canPrompt(
            completedSwipes: 20,
            lastPromptAt: now.addingTimeInterval(-ReliabilityPromptPolicy.cooldown),
            hasVote: false,
            now: now
        ))
    }

    func testNeverPromptsForAnAlreadyRatedCard() {
        XCTAssertFalse(ReliabilityPromptPolicy.canPrompt(
            completedSwipes: 20, lastPromptAt: nil, hasVote: true
        ))
    }
}
