import SwiftUI

// Variant C — two-column staggered grid.
//
// The premise: browsing many gift ideas is a scanning task, and one full-width
// card per item makes you scroll through four screens to see four products. A
// two-column grid puts eight in the same space, so comparison happens by eye
// instead of by memory.
//
// Everything not needed to CHOOSE is deferred to the detail sheet: no vendor
// row, no social icons, no reason line. Image, price, title, save.
//
// Column balancing is greedy-by-height rather than alternating, because
// alternating leaves one column visibly longer whenever aspect ratios differ —
// the classic ragged-Pinterest-column artefact.
struct MasonryFeedGrid: View {
    let posts: [Post]
    var savedIds: Set<String> = []
    var onTap: (Post) -> Void
    var onSave: (Post) -> Void

    private let spacing: CGFloat = 10

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                LazyVStack(spacing: spacing) {
                    ForEach(column) { post in
                        MasonryTile(
                            post: post,
                            isSaved: savedIds.contains(post.id),
                            onTap: { onTap(post) },
                            onSave: { onSave(post) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, 14)
    }

    /// Deal each item to whichever column is currently shorter, estimating tile
    /// height from its aspect ratio.
    private var columns: [[Post]] {
        var result: [[Post]] = [[], []]
        var heights: [CGFloat] = [0, 0]
        for post in posts {
            let index = heights[0] <= heights[1] ? 0 : 1
            result[index].append(post)
            heights[index] += MasonryTile.estimatedHeight(for: post)
        }
        return result
    }
}

struct MasonryTile: View {
    let post: Post
    var isSaved: Bool
    var onTap: () -> Void
    var onSave: () -> Void

    /// Deterministic per post, so a tile keeps its shape between reloads — a
    /// grid whose tiles resize on refresh feels broken.
    ///
    /// No 1:1. A square is what makes a masonry grid look like a plain grid:
    /// every row lines up and the stagger disappears. Two portrait ratios far
    /// enough apart (4:5 and 2:3) give the columns a visible offset while
    /// staying tall enough that product photography is not letterboxed.
    static func aspect(for post: Post) -> CGFloat {
        // The REAL shape wins whenever the source told us. Instagram posts
        // carry true dimensions, and forcing a 1:1 keepsake photo into 2:3
        // crops away the composition the poster framed — which is the whole
        // value of using their photography.
        if let real = post.aspectRatio, real > 0.2, real < 3 {
            // Clamped so one extreme panorama or a 9:16 story cover cannot
            // blow a grid column's height out.
            return CGFloat(min(max(real, 0.62), 1.25))
        }
        // Unknown shape → a stable pseudo-random portrait so the stagger still
        // reads. Hashed on id, so a tile keeps its shape between reloads.
        return AvatarPalette.stableHash(post.id) % 2 == 0 ? 4.0 / 5.0 : 2.0 / 3.0
    }

    static func estimatedHeight(for post: Post) -> CGFloat {
        // Unit width; the text block is roughly constant.
        1 / aspect(for: post) + 0.42
    }

    var body: some View {
        // The IMAGE is the card. There is no container behind it: a rounded
        // panel around every photo added a second border to something that
        // already had edges, and on a dark theme those panels read as grey
        // boxes with pictures inside rather than as products.
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                CachedAsyncImage(url: post.product.image, width: 800)
                    .aspectRatio(Self.aspect(for: post), contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()

                Button(action: onSave) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isSaved ? Color.coral : Color.onPrimary)
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel(isSaved ? "Saved" : "Save")
            }
            .overlay(alignment: .bottomLeading) {
                if post.product.price > 0 {
                    Text(post.product.price.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        // Material, not a solid scrim: it picks up the photo
                        // behind it, so the pill sits ON the image instead of
                        // punching a hole in it.
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(post.product.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
