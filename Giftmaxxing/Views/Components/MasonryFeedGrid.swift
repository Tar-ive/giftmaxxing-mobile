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
    var repeatCount = 1
    var savedIds: Set<String> = []
    var onTap: (Post) -> Void
    var onSave: (Post) -> Void

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: ThemeSpacing.xs, alignment: .top), count: 2),
            alignment: .leading,
            spacing: ThemeSpacing.sm
        ) {
            ForEach(Array(displayPosts.enumerated()), id: \.offset) { index, post in
                MasonryTile(
                    post: post,
                    isSaved: savedIds.contains(post.id),
                    autoplaysGallery: index % 4 == 3,
                    onTap: { onTap(post) },
                    onSave: { onSave(post) }
                )
            }
        }
        .padding(.horizontal, ThemeSpacing.md)
    }

    /// Three static cards, then one curated source carousel. Repeated cycles
    /// use index identity so the same approved catalog can extend indefinitely.
    private var displayPosts: [Post] {
        guard !posts.isEmpty else { return [] }
        let galleries = posts.filter { $0.product.gallery.count > 1 }
        let cards = posts.filter { $0.product.gallery.count <= 1 }
        guard !galleries.isEmpty, !cards.isEmpty else {
            return (0..<max(1, repeatCount)).flatMap { _ in posts }
        }
        let total = max(posts.count, 4) * max(1, repeatCount)
        var cardIndex = 0
        var galleryIndex = 0
        return (0..<total).map { index in
            if index % 4 == 3 {
                defer { galleryIndex += 1 }
                return galleries[galleryIndex % galleries.count]
            }
            defer { cardIndex += 1 }
            return cards[cardIndex % cards.count]
        }
    }
}

struct MasonryTile: View {
    let post: Post
    var isSaved: Bool
    var autoplaysGallery = false
    var onTap: () -> Void
    var onSave: () -> Void

    static func aspect(for post: Post) -> CGFloat { MediaAspect.recommendationCard }

    var body: some View {
        // The IMAGE is the card. There is no container behind it: a rounded
        // panel around every photo added a second border to something that
        // already had edges, and on a dark theme those panels read as grey
        // boxes with pictures inside rather than as products.
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                galleryImage

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
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))

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

    @ViewBuilder
    private var galleryImage: some View {
        Group {
            if autoplaysGallery, post.product.gallery.count > 1 {
                TimelineView(.periodic(from: .now, by: 3)) { timeline in
                    let tick = Int(timeline.date.timeIntervalSinceReferenceDate / 3)
                    let gallery = post.product.gallery
                    CachedAsyncImage(url: gallery[tick % gallery.count], width: 800)
                }
                .accessibilityLabel("Autoplay carousel for \(post.product.name)")
            } else {
                CachedAsyncImage(url: post.product.image, width: 800)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(Self.aspect(for: post), contentMode: .fit)
        .clipped()
    }
}
