import XCTest
import SwiftUI
@testable import Giftmaxxing

final class AvatarPaletteTests: XCTestCase {

    // MARK: - Stability

    func testHashIsStableAcrossCalls() {
        // Swift's built-in hashValue is seeded per process; if this ever starts
        // using it, avatars change colour on every launch.
        let first = AvatarPalette.hue(for: "Saksham Adhikari")
        let second = AvatarPalette.hue(for: "Saksham Adhikari")
        XCTAssertEqual(first, second)
    }

    func testHashIsCaseInsensitive() {
        XCTAssertEqual(
            AvatarPalette.hue(for: "allbirds"),
            AvatarPalette.hue(for: "Allbirds")
        )
    }

    func testDifferentNamesGetDifferentHues() {
        let names = ["Saksham", "Thaman", "Allbirds", "Gymshark", "Morphe", "Cuts"]
        let hues = Set(names.map { AvatarPalette.hue(for: $0) })
        // Collisions are possible in principle; six short names should not.
        XCTAssertEqual(hues.count, names.count)
    }

    // MARK: - Initials

    func testInitialsAreAlwaysUppercase() {
        // The bug this replaced: two-word names skipped .uppercased() entirely,
        // so "cozy oats" rendered as "co".
        XCTAssertEqual(AvatarPalette.initials(for: "cozy oats"), "CO")
        XCTAssertEqual(AvatarPalette.initials(for: "Saksham Adhikari"), "SA")
        XCTAssertEqual(AvatarPalette.initials(for: "allbirds"), "AL")
        XCTAssertEqual(AvatarPalette.initials(for: "shopify_colourpop"), "SC")
        XCTAssertEqual(AvatarPalette.initials(for: "taylor-stitch"), "TS")
    }

    func testInitialsHandleEmptyAndSingleCharacter() {
        XCTAssertEqual(AvatarPalette.initials(for: ""), "")
        XCTAssertEqual(AvatarPalette.initials(for: "x"), "X")
    }

    // MARK: - Contrast (the reason lightness is solved, not fixed)

    /// White initials must clear WCAG AA (4.5:1) on EVERY hue.
    ///
    /// A fixed l=45% fails this badly: yellow (hue 60) measures 2.00:1 — worse
    /// than the muted olive it replaced. This is the test that keeps anyone
    /// from "simplifying" the solve back to a constant.
    func testEveryHueClearsAAAgainstWhiteInitials() {
        for hue in stride(from: 0.0, to: 360.0, by: 5.0) {
            let lightness = AvatarPalette.accessibleLightness(forHue: hue)
            let ratio = Self.contrastWithWhite(hue: hue, saturation: 0.65, lightness: lightness)
            XCTAssertGreaterThanOrEqual(
                ratio, 4.5,
                "hue \(hue) only reached \(String(format: "%.2f", ratio)):1 at lightness \(lightness)"
            )
        }
    }

    func testHuesThatAlreadyPassKeepFullVibrance() {
        // Blues/purples are legible at the base lightness — darkening them
        // would throw away saturation for nothing.
        for hue in [210.0, 240.0, 270.0] {
            XCTAssertEqual(AvatarPalette.accessibleLightness(forHue: hue), 0.45, accuracy: 0.001)
        }
    }

    func testYellowGreenBandIsDarkenedBelowBase() {
        for hue in [60.0, 90.0, 120.0] {
            XCTAssertLessThan(
                AvatarPalette.accessibleLightness(forHue: hue), 0.45,
                "hue \(hue) is the band that fails at base lightness and must be darkened"
            )
        }
    }

    // MARK: - Brand icons

    func testBrandIconURLFromBareHostAndURL() {
        XCTAssertEqual(
            AvatarPalette.brandIconURL(domain: "allbirds.com"),
            "https://allbirds.com/apple-touch-icon.png"
        )
        XCTAssertEqual(
            AvatarPalette.brandIconURL(domain: "www.Allbirds.com"),
            "https://allbirds.com/apple-touch-icon.png"
        )
        XCTAssertEqual(
            AvatarPalette.brandIconURL(domain: "https://shop.gymshark.com/products/x"),
            "https://shop.gymshark.com/apple-touch-icon.png"
        )
    }

    func testBrandIconURLRejectsNonDomains() {
        XCTAssertNil(AvatarPalette.brandIconURL(domain: nil))
        XCTAssertNil(AvatarPalette.brandIconURL(domain: ""))
        XCTAssertNil(AvatarPalette.brandIconURL(domain: "Saksham Adhikari"))
        XCTAssertNil(AvatarPalette.brandIconURL(domain: "localhost"))
    }

    // MARK: - Helpers

    /// WCAG 2.1 contrast of white against an HSL colour.
    private static func contrastWithWhite(hue: Double, saturation: Double, lightness: Double) -> Double {
        let c = (1 - abs(2 * lightness - 1)) * saturation
        let hp = hue / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double)
        switch hp {
        case ..<1: (r1, g1, b1) = (c, x, 0)
        case ..<2: (r1, g1, b1) = (x, c, 0)
        case ..<3: (r1, g1, b1) = (0, c, x)
        case ..<4: (r1, g1, b1) = (0, x, c)
        case ..<5: (r1, g1, b1) = (x, 0, c)
        default:   (r1, g1, b1) = (c, 0, x)
        }
        let m = lightness - c / 2
        func channel(_ v: Double) -> Double {
            let v = v + m
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channel(r1) + 0.7152 * channel(g1) + 0.0722 * channel(b1)
        return 1.05 / (luminance + 0.05)
    }
}
