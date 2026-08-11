import XCTest
@testable import Giftmaxxing

final class CuratedGiftStoreTests: XCTestCase {
    private let store = CuratedGiftStore.shared

    func testPilotContainsOnlyManuallyApprovedSources() {
        XCTAssertEqual(
            Set(store.catalog.journeys.map(\.sourcePostId)),
            Set([
                "7670641859131100430",
                "7670641318242077966",
                "7672135662056869133",
                "7670644980880248077",
            ])
        )
    }

    func testEveryRecommendationHasEvidenceAndAValidMerchantURL() {
        let products = store.catalog.journeys.flatMap(\.products) + store.catalog.wrapKit
        XCTAssertFalse(products.isEmpty)
        for product in products {
            XCTAssertFalse(product.matchEvidence.isEmpty, product.id)
            XCTAssertFalse(product.capabilities.isEmpty, product.id)
            XCTAssertEqual(URL(string: product.productUrl)?.scheme, "https", product.id)
        }
    }

    func testBundledImagesResolve() {
        let images = store.catalog.journeys.flatMap(\.images)
        XCTAssertFalse(images.isEmpty)
        for image in images {
            let filename = String(image.dropFirst("bundle:///".count))
            let resource = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            let url = Bundle.main.url(forResource: resource, withExtension: ext, subdirectory: "Curated")
                ?? Bundle.main.url(forResource: resource, withExtension: ext)
            XCTAssertNotNil(url, filename)
        }
    }

    func testSearchNeverReturnsLegacyCatalogItems() {
        XCTAssertTrue(CuratedGiftStore.isPilotEnabled)
        XCTAssertTrue(store.search("cashmere").allSatisfy { $0.id.hasPrefix("curated-product-") })
    }
}
