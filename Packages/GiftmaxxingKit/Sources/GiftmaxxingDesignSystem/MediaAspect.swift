// The design system is UIKit-backed (UIColor trait resolution, UIViewRepresentable
// pickers, UIImage caching), so it only exists where UIKit does. The guard keeps
// `swift build` / `swift test` working natively on macOS for the other three
// targets — which is what makes the sub-second test loop possible.
#if canImport(UIKit)
import CoreGraphics
import GiftmaxxingCore

// User-uploaded media renders in exactly TWO shapes — vertical (9:16
// short-form) and square (1:1) — and the app adapts to whichever the upload
// actually is. Anything landscape is shown square rather than letterboxed
// into a 16:9 band, so the feed never has a horizontal card.
public enum MediaAspect {
    public static let vertical: CGFloat = 9.0 / 16.0
    public static let square: CGFloat = 1.0
    /// Product (non-UGC) imagery keeps the editorial 4:5 portrait crop.
    public static let product: CGFloat = 4.0 / 5.0
    /// RedNote-style discovery cards share one portrait frame. A single ratio
    /// keeps both columns aligned and prevents the same item changing shape
    /// between the feed and its detail view.
    public static let recommendationCard: CGFloat = 3.0 / 4.0

    /// Widescreen uploads (16:9 screenshots, screen recordings, 4-up collages)
    /// keep their real shape. They used to snap to square, which cropped the
    /// top and bottom off — on a collage that means slicing through the images
    /// and any caption text baked into them.
    public static let landscape: CGFloat = 16.0 / 9.0

    /// Snap a measured width/height ratio onto the supported shapes.
    /// Meaningfully taller than square → vertical; meaningfully wider →
    /// landscape; everything in between → square.
    public static func snap(_ ratio: CGFloat) -> CGFloat {
        guard ratio.isFinite, ratio > 0 else { return square }
        if ratio < 0.9 { return vertical }
        // 1.25 is the midpoint between square and 4:3 — anything past it is
        // clearly a wide image and is better letter-boxed than cropped.
        if ratio > 1.25 { return min(ratio, landscape) }
        return square
    }

    public static func snap(width: CGFloat, height: CGFloat) -> CGFloat {
        guard height > 0 else { return square }
        return snap(width / height)
    }
}


#endif
