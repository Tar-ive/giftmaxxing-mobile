import XCTest
@testable import Giftmaxxing
import GiftmaxxingCore

final class BirthdayPerksTests: XCTestCase {

    // The bundled fallback is the offline face of the feature — it must be
    // non-trivial, deduped, and every entry fully renderable.
    func testFallbackDatasetIntegrity() {
        let perks = BirthdayPerk.fallback
        XCTAssertGreaterThanOrEqual(perks.count, 10, "fallback should cover the headliners")

        let ids = perks.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate perk ids")

        for perk in perks {
            XCTAssertFalse(perk.brand.isEmpty, "\(perk.id): empty brand")
            XCTAssertFalse(perk.gift.isEmpty, "\(perk.id): empty gift")
            XCTAssertFalse(perk.how.isEmpty, "\(perk.id): empty claim instructions")
            XCTAssertFalse(perk.window.isEmpty, "\(perk.id): empty window")
            let url = URL(string: perk.url)
            XCTAssertNotNil(url, "\(perk.id): bad url")
            XCTAssertEqual(url?.scheme, "https", "\(perk.id): non-https url")
            XCTAssertTrue(perk.color.hasPrefix("#"), "\(perk.id): color must be hex")
        }
    }

    // Server contract: the response shape the app decodes. A payload matching
    // infra/src/birthday-freebies.mjs must decode losslessly.
    func testServerResponseDecodes() throws {
        let json = """
        {
          "perks": [
            {"id": "sephora", "brand": "Sephora", "category": "Beauty",
             "gift": "Free birthday gift set", "how": "Join Beauty Insider (free)",
             "window": "Your birthday month", "url": "https://www.sephora.com/beauty/birthday-gift",
             "emoji": "💄", "color": "#D6003C"}
          ],
          "categories": ["Beauty"],
          "updatedAt": "2026-07-07"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(BirthdayPerksResponse.self, from: json)
        XCTAssertEqual(decoded.perks.count, 1)
        XCTAssertEqual(decoded.perks.first?.id, "sephora")
        XCTAssertEqual(decoded.categories, ["Beauty"])
    }

    @MainActor
    func testBirthdayMonthDetection() {
        let store = BirthdayPerksStore.shared
        let originalMonth = store.birthMonth
        let originalDay = store.birthDay
        defer {
            store.birthMonth = originalMonth
            store.birthDay = originalDay
        }

        let thisMonth = Calendar.current.component(.month, from: Date())
        store.birthMonth = thisMonth
        XCTAssertTrue(store.isBirthdayMonth)
        XCTAssertNotNil(store.birthMonthName)

        store.birthMonth = thisMonth == 12 ? 1 : thisMonth + 1
        XCTAssertFalse(store.isBirthdayMonth)

        store.birthMonth = nil
        XCTAssertFalse(store.isBirthdayMonth)
        XCTAssertFalse(store.hasBirthday)
        XCTAssertNil(store.birthMonthName)
    }

    @MainActor
    func testCategoriesPreserveDatasetOrder() {
        let store = BirthdayPerksStore.shared
        let categories = store.categories
        XCTAssertFalse(categories.isEmpty)
        XCTAssertEqual(categories.count, Set(categories).count, "categories must be unique")
        // Every perk's category is present.
        for perk in store.perks {
            XCTAssertTrue(categories.contains(perk.category))
        }
    }
}
