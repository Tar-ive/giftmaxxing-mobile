import XCTest
@testable import GiftmaxxingRecommendation
import GiftmaxxingCore

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

    // ── Non-giftable merchandise gate (parity with quality.test.mjs) ─────────

    func testReplacementAutoPartIsNonGiftDespiteRetailerAndPrice() {
        // Live feed example (eBay import) — passed every commerce heuristic.
        let q = ContentQuality.classify(
            title: "Bm1240164 Replacement Front Driver Side Fender Fits 2014-2016 Bmw 428i",
            domain: "ebay.com",
            link: "https://www.ebay.com/itm/123",
            price: 89
        )
        XCTAssertEqual(q.contentType, .nonGift)
        XCTAssertFalse(q.feedEligible)
    }

    func testWasherFluidReservoirIsNonGift() {
        let q = ContentQuality.classify(
            title: "To1288213 Replacement Washer Fluid Reservoir Fits 2013-2018 Toyota Rav4",
            domain: "ebay.com", link: nil, price: 49
        )
        XCTAssertEqual(q.contentType, .nonGift)
        XCTAssertFalse(q.feedEligible)
    }

    func testDoorLockActuatorIsNonGift() {
        // Live feed example — neither "replacement" nor a fits-years pattern.
        let q = ContentQuality.classify(
            title: "Door Lock Actuator Motor Dorman 937-080",
            domain: "ebay.com", link: nil, price: 232
        )
        XCTAssertEqual(q.contentType, .nonGift)
        XCTAssertFalse(q.feedEligible)
    }

    func testWheelStudWithAutoBrandIsNonGift() {
        let q = ContentQuality.classify(
            title: "Dorman 610368.1 Wheel Stud",
            domain: "ebay.com", link: nil, price: 12
        )
        XCTAssertEqual(q.contentType, .nonGift)
        XCTAssertFalse(q.feedEligible)
    }

    func testPlumbingHardwareIsNonGift() {
        let q = ContentQuality.classify(
            title: "Kitchen Sink Strainer Drain Assembly, Stainless Steel",
            domain: "lowes.com", link: nil, price: 18
        )
        XCTAssertEqual(q.contentType, .nonGift)
        XCTAssertFalse(q.feedEligible)
    }

    func testDigitalPdfPatternIsNonGift() {
        // Live feed example (Etsy import) — a $7 digital file, not a gift.
        let q = ContentQuality.classify(
            title: "PDF File for Crochet Pattern (English), Junction Beanie, Pictures and Video Tutorials Included",
            domain: "etsy.me", link: nil, price: 7
        )
        XCTAssertEqual(q.contentType, .nonGift)
        XCTAssertFalse(q.feedEligible)
    }

    func testPriceMentioningGiftIsNotAListicle() {
        // Live regression: this AirPods caption was classified gift_guide by
        // the N-gifts regex matching "$200 … gift" — a price, not a roundup.
        let q = ContentQuality.classify(
            title: "Open-ear comfort with real ANC — the under-$200 Apple gift.",
            domain: "amazon.com", link: nil, price: 179
        )
        XCTAssertEqual(q.contentType, .singleProduct)
        XCTAssertTrue(q.feedEligible)
    }

    func testFenderGuitarIsNotAnAutoPart() {
        // "Fender" is ambiguous — without automotive context it must stay eligible.
        let q = ContentQuality.classify(
            title: "Vintage Fender Stratocaster Miniature Guitar Model",
            domain: "etsy.com", link: nil, price: 30
        )
        XCTAssertEqual(q.contentType, .singleProduct)
        XCTAssertTrue(q.feedEligible)
    }

    func testHandmadeCrochetBeanieIsNotADigitalPattern() {
        let q = ContentQuality.classify(
            title: "Crochet Beanie, Handmade Wool Hat",
            domain: "etsy.com", link: nil, price: 24
        )
        XCTAssertEqual(q.contentType, .singleProduct)
        XCTAssertTrue(q.feedEligible)
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
