import Foundation
import GiftmaxxingCore

// ── Intentionality — the differentiator ──────────────────────────────────────
// A meta-feature of the GIFT itself: does it carry a story worth telling, does
// it come from an independent maker, is it a real committed listing? We bias
// toward high intentionality, not just high ratings.
public enum IntentionalityScore {
    public static func score(for post: Post) -> Double {
        var s = 0.0
        // A story (maker's description / provenance) — length-scaled.
        if let story = GiftStory.story(for: post) {
            s += 0.35 + min(0.15, Double(story.count) / 2000)
        }
        // Independent-maker origin.
        if GiftStory.isSmallBusiness(post) { s += 0.25 }
        // Curated services are deliberate picks by design.
        if post.isService { s += 0.15 }
        // A real, committed listing: price + photo.
        if post.product.price > 0 { s += 0.10 }
        if post.product.image != nil { s += 0.05 }
        // Multi-shot galleries signal a seller who cares about presentation.
        if post.product.gallery.count > 2 { s += 0.10 }
        return min(1, s)
    }
}
