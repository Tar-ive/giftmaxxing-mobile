import CoreGraphics

// User-uploaded media renders in exactly TWO shapes — vertical (9:16
// short-form) and square (1:1) — and the app adapts to whichever the upload
// actually is. Anything landscape is shown square rather than letterboxed
// into a 16:9 band, so the feed never has a horizontal card.
enum MediaAspect {
    static let vertical: CGFloat = 9.0 / 16.0
    static let square: CGFloat = 1.0
    /// Product (non-UGC) imagery keeps the editorial 4:5 portrait crop.
    static let product: CGFloat = 4.0 / 5.0

    /// Snap a measured width/height ratio onto the supported shapes.
    /// Meaningfully taller than square → vertical; everything else → square.
    static func snap(_ ratio: CGFloat) -> CGFloat {
        guard ratio.isFinite, ratio > 0 else { return square }
        return ratio < 0.9 ? vertical : square
    }

    static func snap(width: CGFloat, height: CGFloat) -> CGFloat {
        guard height > 0 else { return square }
        return snap(width / height)
    }
}
