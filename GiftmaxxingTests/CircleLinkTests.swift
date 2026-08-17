import XCTest
@testable import Giftmaxxing
import GiftmaxxingCore

// Cross-platform contract with the web circle page (web/lib/circles.ts):
// link parsing must accept every shape a member might paste, and the date
// math must agree with the web's nextOccurrence/turningAge so both platforms
// show the same countdowns.
@MainActor
final class CircleLinkTests: XCTestCase {

    // ── Link parsing ─────────────────────────────────────────────────────────

    func testParsesWebShareURL() {
        XCTAssertEqual(
            CircleStore.circleId(fromText: "https://giftmaxxing-web.vercel.app/circle/cir_7a36a49b-8d2b-4a10-a399-b7055075aafa"),
            "cir_7a36a49b-8d2b-4a10-a399-b7055075aafa"
        )
    }

    func testParsesLinkPastedWithSurroundingChatText() {
        let text = "Join our \"Sharma Family\" gift circle 🎁 https://giftmaxxing-web.vercel.app/circle/cir_abc123 — add your birthday!"
        XCTAssertEqual(CircleStore.circleId(fromText: text), "cir_abc123")
    }

    func testParsesBareId() {
        XCTAssertEqual(CircleStore.circleId(fromText: "cir_abc123"), "cir_abc123")
    }

    func testRejectsTextWithoutId() {
        XCTAssertNil(CircleStore.circleId(fromText: "https://example.com/nothing-here"))
    }

    func testParsesDeepLinkURL() throws {
        let url = try XCTUnwrap(URL(string: "giftmaxxing://circle/cir_abc123"))
        XCTAssertEqual(CircleStore.circleId(fromURL: url), "cir_abc123")
    }

    func testParsesHTTPSCircleURL() throws {
        let url = try XCTUnwrap(URL(string: "https://giftmaxxing-web.vercel.app/circle/cir_abc123"))
        XCTAssertEqual(CircleStore.circleId(fromURL: url), "cir_abc123")
    }

    func testRejectsUnrelatedURLEvenWithCirPrefixElsewhere() throws {
        // "cir_" appearing outside a circle link must not hijack routing.
        let url = try XCTUnwrap(URL(string: "https://example.com/product/cir_notacircle"))
        XCTAssertNil(CircleStore.circleId(fromURL: url))
    }

    // ── Date math (web/lib/circles.ts parity) ────────────────────────────────

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testNextOccurrenceRollsToNextYearWhenPassed() throws {
        let now = date(2026, 7, 6)
        let next = try XCTUnwrap(CircleMoment.nextOccurrence(ofYMD: "1990-03-14", from: now))
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: next)
        XCTAssertEqual(comps.year, 2027)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 14)
    }

    func testNextOccurrenceStaysThisYearWhenAhead() throws {
        let now = date(2026, 7, 6)
        let next = try XCTUnwrap(CircleMoment.nextOccurrence(ofYMD: "1990-12-25", from: now))
        XCTAssertEqual(Calendar.current.component(.year, from: next), 2026)
        XCTAssertEqual(CircleMoment.daysUntil(next, from: now), 172)
    }

    func testTodayCountsAsZeroDays() throws {
        let now = date(2026, 7, 6)
        let next = try XCTUnwrap(CircleMoment.nextOccurrence(ofYMD: "2000-07-06", from: now))
        XCTAssertEqual(CircleMoment.daysUntil(next, from: now), 0)
    }

    func testTurningAgeWithRealYear() {
        // Born 1990, birthday already passed in 2026 → turns 37 in 2027.
        XCTAssertEqual(CircleMoment.turningAge(birthday: "1990-03-14", from: date(2026, 7, 6)), 37)
        // Birthday still ahead in 2026 → turns 36 this year.
        XCTAssertEqual(CircleMoment.turningAge(birthday: "1990-12-25", from: date(2026, 7, 6)), 36)
    }

    func testTurningAgeHiddenForPlaceholderYears() {
        // Web parity: years before 1900 or in the future mean "don't show age".
        XCTAssertNil(CircleMoment.turningAge(birthday: "1600-01-01", from: date(2026, 7, 6)))
        XCTAssertNil(CircleMoment.turningAge(birthday: "2030-01-01", from: date(2026, 7, 6)))
    }
}
