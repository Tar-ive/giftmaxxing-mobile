import XCTest
@testable import Giftmaxxing

// Stage-1 feed gate. Parity contract with infra/src/quality.mjs — if these
// break, junk (listicles/recipes/blog spam) leaks into the scroll feed or real
// products get dropped.
final class ContentQualityTests: XCTestCase {

    func testListicleTitleIsGiftGuideAndIneligible() {
        let q = ContentQuality.classify(
            title: "27 Best Gifts for Dads Who Have Everything",
            domain: nil, link: nil, price: nil
        )
        XCTAssertEqual(q.contentType, .giftGuide)
        XCTAssertFalse(q.feedEligible)
    }

    func testGiftIdeasPhraseIsIneligibleEvenWithPrice() {
        let q = ContentQuality.classify(
            title: "Gift ideas for your bestie",
            domain: "etsy.com", link: nil, price: 25
        )
        XCTAssertEqual(q.contentType, .giftGuide)
        XCTAssertFalse(q.feedEligible)
    }

    func testRetailerProductWithPriceIsEligibleHighQuality() {
        let q = ContentQuality.classify(
            title: "Handmade Ceramic Coffee Mug",
            domain: "etsy.com",
            link: "https://www.etsy.com/listing/12345/handmade-ceramic-mug",
            price: 32
        )
        XCTAssertEqual(q.contentType, .singleProduct)
        XCTAssertTrue(q.feedEligible)
        XCTAssertGreaterThan(q.qualityScore, 0.8)
    }

    func testRecipeDomainIsNeverEligible() {
        let q = ContentQuality.classify(
            title: "Creamy Tuscan Chicken",
            domain: "allrecipes.com", link: nil, price: nil
        )
        XCTAssertEqual(q.contentType, .recipe)
        XCTAssertFalse(q.feedEligible)
    }

    func testBlogDomainIsSpam() {
        let q = ContentQuality.classify(
            title: "Cute finds",
            domain: "goodmomliving.com", link: nil, price: nil
        )
        XCTAssertEqual(q.contentType, .spam)
        XCTAssertFalse(q.feedEligible)
    }

    func testBlogspotSuffixIsSpam() {
        let q = ContentQuality.classify(
            title: "My haul",
            domain: "somebody.blogspot.com", link: nil, price: nil
        )
        XCTAssertEqual(q.contentType, .spam)
        XCTAssertFalse(q.feedEligible)
    }

    func testWwwPrefixIsNormalized() {
        let q = ContentQuality.classify(
            title: "Weighted Blanket",
            domain: "www.target.com", link: nil, price: 49
        )
        XCTAssertEqual(q.contentType, .singleProduct)
        XCTAssertTrue(q.feedEligible)
        XCTAssertGreaterThan(q.qualityScore, 0.8)
    }

    func testUnknownDomainNoPriceStillProductButLowerQuality() {
        let q = ContentQuality.classify(
            title: "Linen Apron", domain: "someshop.example", link: nil, price: nil
        )
        XCTAssertEqual(q.contentType, .singleProduct)
        XCTAssertTrue(q.feedEligible)
        XCTAssertLessThan(q.qualityScore, 0.6)
    }

    func testQualityScoreIsClampedToOne() {
        let q = ContentQuality.classify(
            title: "Mug",
            domain: "amazon.com",
            link: "https://amazon.com/dp/B000123",
            price: 12
        )
        XCTAssertLessThanOrEqual(q.qualityScore, 1.0)
        XCTAssertGreaterThanOrEqual(q.qualityScore, 0.0)
    }
}
