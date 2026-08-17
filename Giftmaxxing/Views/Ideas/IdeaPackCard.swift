import SwiftUI
import GiftmaxxingCore

// One card for both kinds of pack. Galleries lead with a single cover image
// (the shelf's mood); bundles lead with a collage, because the pairing IS the
// content — seeing three things side by side is the whole pitch.
struct IdeaPackCard: View {
    let pack: IdeaPack
    /// Fixed width in a horizontal rail; nil lets the card fill a grid cell.
    var width: CGFloat? = 210

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
                .frame(width: width, height: 120)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(pack.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(pack.subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.inkTertiary)
                    .lineLimit(1)
            }
            .padding(.top, ThemeSpacing.xs)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pack.title), \(pack.subtitle)")
    }

    @ViewBuilder
    private var cover: some View {
        switch pack.kind {
        case .gallery:
            ZStack(alignment: .bottomLeading) {
                Color.gradient(for: pack.grad)
                if let image = pack.coverImage {
                    CachedAsyncImage(url: image, width: 500)
                } else {
                    Image(systemName: pack.symbol)
                        .font(.title.weight(.medium))
                        .foregroundStyle(Color.onPrimary.opacity(0.9))
                        .padding(ThemeSpacing.sm)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }

        case .bundle:
            HStack(spacing: 3) {
                ForEach(pack.sections.prefix(3)) { section in
                    ZStack {
                        Color.gradient(for: pack.grad)
                        if let image = section.items.first?.product.image {
                            CachedAsyncImage(url: image, width: 300)
                        } else if let emoji = section.emoji {
                            Text(emoji).font(.title3)
                        }
                    }
                }
            }
        }
    }
}
