import XCTest
@testable import Giftmaxxing
import GiftmaxxingCore

// Amazon affiliate routing: ASIN extraction, retagging (web outboundAffiliateUrl
// parity) and universal-link eligibility (docs/amazon-app-linking.md).
final class AffiliateTests: XCTestCase {

    // MARK: extractAsin

    func testExtractAsinFromDpPath() {
        XCTAssertEqual(Affiliate.extractAsin(from: "https://www.amazon.com/dp/B0ABC12345?ref=x"), "B0ABC12345")
    }

    func testExtractAsinFromGpProductPath() {
        XCTAssertEqual(Affiliate.extractAsin(from: "https://amazon.com/gp/product/B0XYZ98765"), "B0XYZ98765")
    }

    func testExtractAsinFromBareAsin() {
        XCTAssertEqual(Affiliate.extractAsin(from: "b0abc12345"), "B0ABC12345")
    }

    func testExtractAsinRejectsNonAmazonShapes() {
        XCTAssertNil(Affiliate.extractAsin(from: "https://www.sephora.com/product/P12345"))
        XCTAssertNil(Affiliate.extractAsin(from: "https://www.amazon.com/s?k=candles"))
    }

    // MARK: retag

    func testRetagRebuildsUntaggedDpLink() {
        let url = URL(string: "https://www.amazon.com/Some-Product-Name/dp/B0ABC12345?ref=sr_1_3&pf_rd=junk")!
        let out = Affiliate.retag(url)
        XCTAssertEqual(out.absoluteString, "https://www.amazon.com/dp/B0ABC12345?tag=\(Affiliate.associateTag)")
    }

    func testRetagAppendsTagToSearchLink() {
        let url = URL(string: "https://www.amazon.com/s?k=gardening+gifts")!
        let out = Affiliate.retag(url)
        XCTAssertTrue(out.absoluteString.contains("tag=\(Affiliate.associateTag)"))
        XCTAssertTrue(out.absoluteString.contains("k=gardening+gifts"))
    }

    func testRetagKeepsExistingTag() {
        let url = URL(string: "https://www.amazon.com/s?k=mugs&tag=\(Affiliate.associateTag)")!
        let out = Affiliate.retag(url)
        XCTAssertEqual(out.absoluteString.components(separatedBy: "tag=").count, 2)
    }

    func testRetagLeavesNonAmazonUrlsUntouched() {
        let url = URL(string: "https://www.urbanoutfitters.com/shop/cool-lamp")!
        XCTAssertEqual(Affiliate.retag(url), url)
    }

    // MARK: universal-link eligibility

    func testAmazonMarketplacesAreEligible() {
        XCTAssertTrue(Affiliate.isAppLinkEligible(URL(string: "https://www.amazon.com/dp/B0ABC12345")!))
        XCTAssertTrue(Affiliate.isAppLinkEligible(URL(string: "https://amazon.co.uk/dp/B0ABC12345")!))
        XCTAssertTrue(Affiliate.isAppLinkEligible(URL(string: "https://a.co/d/abc1234")!))
    }

    func testAmznToShortlinksAreNotEligible() {
        // Bitly-managed domain — no Amazon AASA, must stay in the browser path.
        XCTAssertFalse(Affiliate.isAppLinkEligible(URL(string: "https://amzn.to/3xYzAbC")!))
    }

    func testLookalikeDomainsAreNotEligible() {
        XCTAssertFalse(Affiliate.isAppLinkEligible(URL(string: "https://fakeamazon.company.com/dp/B0ABC12345")!))
        XCTAssertFalse(Affiliate.isAppLinkEligible(URL(string: "https://notamazon.com/deal")!))
    }

    // MARK: productUrl (web outboundAffiliateUrl parity)

    private func makePost(productUrl: String?) -> Post {
        Post(
            id: "post-1",
            user: "tester",
            time: "1h",
            product: Product(id: "p-1", name: "Linen Throw", brand: "Parachute", price: 79, was: nil, grad: .peach, emoji: "🎁", image: nil),
            caption: "so cozy",
            likes: 3,
            productUrl: productUrl
        )
    }

    func testProductUrlRetagsRawAmazonLink() {
        let url = Affiliate.productUrl(for: makePost(productUrl: "https://www.amazon.com/Linen-Throw/dp/B0LINEN123?ref=share"))
        XCTAssertEqual(url?.absoluteString, "https://www.amazon.com/dp/B0LINEN123?tag=\(Affiliate.associateTag)")
    }

    func testProductUrlFallsBackToTaggedSearchForAsinlessAmazonLink() {
        let url = Affiliate.productUrl(for: makePost(productUrl: "https://www.amazon.com/stores/SomeBrand/page/123"))
        let s = url?.absoluteString ?? ""
        XCTAssertTrue(s.contains("/s?k="), "expected tagged search fallback, got \(s)")
        XCTAssertTrue(s.contains("tag=\(Affiliate.associateTag)"))
    }

    func testProductUrlPassesThroughOtherRetailers() {
        let raw = "https://www.sephora.com/product/glow-set-P4813"
        XCTAssertEqual(Affiliate.productUrl(for: makePost(productUrl: raw))?.absoluteString, raw)
    }

    func testProductUrlPinterestFallsBackToTaggedSearch() {
        let url = Affiliate.productUrl(for: makePost(productUrl: "https://pin.it/abc123"))
        XCTAssertTrue((url?.absoluteString ?? "").contains("tag=\(Affiliate.associateTag)"))
    }
}
