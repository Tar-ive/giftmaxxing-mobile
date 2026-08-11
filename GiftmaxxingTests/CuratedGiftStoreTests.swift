import XCTest
@testable import Giftmaxxing

final class CuratedGiftStoreTests: XCTestCase {
    private let store = CuratedGiftStore.shared

    func testPilotContainsEverySuppliedSourceOnce() {
        let ids = store.catalog.journeys.map(\.sourcePostId)
        XCTAssertEqual(ids.count, 21)
        XCTAssertEqual(Set(ids).count, 21)
        XCTAssertEqual(store.sourcePosts.count, 21)
    }

    func testEveryRecommendationHasEvidenceAndAValidMerchantURL() {
        let products = store.catalog.products + store.catalog.wrapKit
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

    func testEveryJourneyProductResolves() {
        let productIds = Set(store.catalog.products.map(\.id))
        for journey in store.catalog.journeys {
            XCTAssertTrue(Set(journey.productIds).isSubset(of: productIds), journey.id)
        }
    }

    func testSourceCardsDoNotExposeInternalCurationCopy() {
        for post in store.sourcePosts {
            XCTAssertNil(post.reason)
            XCTAssertFalse(post.caption.localizedCaseInsensitiveContains("supplied TikTok export"))
        }
    }

    func testSearchNeverReturnsLegacyCatalogItems() {
        XCTAssertTrue(CuratedGiftStore.isPilotEnabled)
        XCTAssertTrue(store.search("cashmere").allSatisfy { $0.id.hasPrefix("curated-product-") })
    }
}
