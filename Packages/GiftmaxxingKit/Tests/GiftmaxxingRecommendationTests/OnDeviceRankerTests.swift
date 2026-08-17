import XCTest
@testable import GiftmaxxingRecommendation
import GiftmaxxingCore

// The layered on-device ranker. Assertions use margins comfortably above the
// random exploration term (W.explore = 0.06) so tests stay deterministic.
final class OnDeviceRankerTests: XCTestCase {

    private func makePost(
        id: String,
        name: String,
        author: String = "author-\(Int.random(in: 0...9999))",
        price: Double = 30,
        likes: Int = 100,
        category: String? = nil
    ) -> Post {
        Post(
            id: id,
            user: author,
            time: "2h",
            product: Product(id: "p-\(id)", name: name, brand: "BrandCo", price: price, was: nil, grad: .peach, emoji: "🎁", image: nil),
            caption: name,
            likes: likes,
            category: category,
            qualityScore: 0.5,
            feedEligible: true
        )
    }

    func testSeenItemsAreFiltered() {
        var profile = TasteSnapshot()
        profile.seen = ["seen-1"]
        let posts = [
            makePost(id: "seen-1", name: "Cozy Blanket"),
            makePost(id: "fresh-1", name: "Ceramic Mug"),
        ]
        let ranked = OnDeviceRanker.rank(candidates: posts, profile: profile)
        XCTAssertEqual(ranked.map(\.post.id), ["fresh-1"])
    }

    func testDuplicateIdsAreDeduped() {
        let posts = [
            makePost(id: "dup", name: "Candle A"),
            makePost(id: "dup", name: "Candle B"),
            makePost(id: "other", name: "Vase"),
        ]
        let ranked = OnDeviceRanker.rank(candidates: posts, profile: TasteSnapshot())
        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(Set(ranked.map(\.post.id)), ["dup", "other"])
    }

    func testFeedIneligibleItemsAreDropped() {
        var junk = makePost(id: "junk", name: "10 Best Gifts for Moms")
        junk.feedEligible = false
        let posts = [junk, makePost(id: "good", name: "Silk Scarf")]
        let ranked = OnDeviceRanker.rank(candidates: posts, profile: TasteSnapshot())
        XCTAssertEqual(ranked.map(\.post.id), ["good"])
    }

    // A strong vibe match (+0.45 max) must beat the 0.06 exploration noise.
    func testVibeMatchOutranksNonMatch() {
        var profile = TasteSnapshot()
        profile.vibes = ["cozy": 2.0]
        profile.totalVibeWeight = 2.0

        let posts = [
            makePost(id: "tech-item", name: "Wireless Charger Gadget", author: "a1", category: "tech"),
            makePost(id: "cozy-item", name: "Fuzzy Knit Blanket Throw", author: "a2", category: "home"),
        ]
        let ranked = OnDeviceRanker.rank(candidates: posts, profile: profile)
        XCTAssertEqual(ranked.first?.post.id, "cozy-item")
    }

    // Regression: a same-category wall spanning MULTIPLE brands ("15 shoes
    // from Vessi/Rothy's/Allbirds back-to-back") must be broken up by the
    // Layer-5 category spacing even though author spacing never triggers.
    func testCategoryWallAcrossBrandsIsSpaced() {
        let shoes = (0..<12).map { i in
            makePost(id: "shoe-\(i)", name: "Runner Sneaker \(i)",
                     author: ["vessi", "rothys", "allbirds"][i % 3],
                     likes: 400, category: "shoes")
        }
        let other = (0..<6).map { i in
            makePost(id: "other-\(i)", name: "Ceramic Mug \(i)",
                     author: "brand-\(i)", likes: 50,
                     category: ["tech", "kitchen", "home"][i % 3])
        }
        let ranked = OnDeviceRanker.rank(candidates: shoes + other, profile: TasteSnapshot())
        let firstTen = ranked.prefix(10)
        // Longest same-category run in the first screen must stay short.
        var longestRun = 0, run = 0
        var prev: String?
        for r in firstTen {
            let c = r.post.category ?? ""
            run = (c == prev) ? run + 1 : 1
            prev = c
            longestRun = max(longestRun, run)
        }
        XCTAssertLessThanOrEqual(longestRun, 4, "category run of \(longestRun) in the first screen")
        XCTAssertFalse(firstTen.allSatisfy { $0.post.category == "shoes" }, "first screen was all shoes")
    }

    // Budget fit: within-budget gets +0.15, far-over-budget bottoms at -0.1 —
    // a 0.25 spread, > explore noise.
    func testBudgetFitOutranksBlownBudget() {
        let posts = [
            makePost(id: "pricey", name: "Marble Sculpture", author: "a1", price: 500),
            makePost(id: "affordable", name: "Marble Coaster", author: "a2", price: 20),
        ]
        var context = RankingContext()
        context.budget = 30
        let ranked = OnDeviceRanker.rank(candidates: posts, profile: TasteSnapshot(), context: context)
        XCTAssertEqual(ranked.first?.post.id, "affordable")
        XCTAssertTrue(ranked.contains { $0.post.id == "pricey" }, "over-budget items are demoted, not dropped")
    }

    func testVectorSimilarityBoostsAndExplains() {
        let posts = [
            makePost(id: "similar", name: "Linen Robe", author: "a1"),
            makePost(id: "unrelated", name: "Desk Fan", author: "a2"),
        ]
        let ranked = OnDeviceRanker.rank(
            candidates: posts,
            profile: TasteSnapshot(),
            vectorSimilarities: ["similar": 0.9]
        )
        XCTAssertEqual(ranked.first?.post.id, "similar")
        XCTAssertEqual(ranked.first?.reason, "Similar to gifts you saved")
    }

    func testEmptyCandidatesReturnsEmpty() {
        XCTAssertTrue(OnDeviceRanker.rank(candidates: [], profile: TasteSnapshot()).isEmpty)
    }
}

// Taste-signal extraction feeding the ranker.
final class TasteSignalsTests: XCTestCase {

    private func post(name: String, caption: String = "", category: String? = nil) -> Post {
        Post(
            id: "t1",
            user: "u",
            time: "1h",
            product: Product(id: "p1", name: name, brand: "", price: 10, was: nil, grad: .sage, emoji: "🎁", image: nil),
            caption: caption,
            likes: 0,
            category: category
        )
    }

    func testCozyKeywordsExtractVibeAndCategory() {
        let s = TasteSignals.extract(from: post(name: "Fuzzy Knit Blanket"))
        XCTAssertTrue(s.vibes.contains("cozy"))
        XCTAssertEqual(s.category, "home")
    }

    func testServerCategoryWinsOverKeywordMapping() {
        let s = TasteSignals.extract(from: post(name: "Fuzzy Blanket", category: "Wellness"))
        XCTAssertEqual(s.category, "wellness")
    }

    func testUnmatchedTextFallsBackToMisc() {
        let s = TasteSignals.extract(from: post(name: "Xylo Quorv"))
        XCTAssertTrue(s.vibes.isEmpty)
        XCTAssertEqual(s.category, "misc")
    }

    func testVibesAreCappedAtFour() {
        let s = TasteSignals.extract(from: post(
            name: "Cozy smart mug with candle spa journal vinyl camera",
            caption: "zen amber outdoor necklace dog puzzle book passport art yoga plant"
        ))
        XCTAssertLessThanOrEqual(s.vibes.count, 4)
        XCTAssertFalse(s.vibes.isEmpty)
    }
}
