// The design system is UIKit-backed (UIColor trait resolution, UIViewRepresentable
// pickers, UIImage caching), so it only exists where UIKit does. The guard keeps
// `swift build` / `swift test` working natively on macOS for the other three
// targets — which is what makes the sub-second test loop possible.
#if canImport(UIKit)
import SwiftUI
import GiftmaxxingCore

public struct GradientCard: View {
    public let grad: GradientStyle
    public let emoji: String
    public var imageURL: String?
    public var size: CGFloat = 120

    public init(
        grad: GradientStyle,
        emoji: String,
        imageURL: String? = nil,
        size: CGFloat = 120
    ) {
        self.grad = grad
        self.emoji = emoji
        self.imageURL = imageURL
        self.size = size
    }


    public var body: some View {
        ZStack {
            Color.gradient(for: grad)

            Text(emoji)
                .font(.system(size: size * 0.4))

            if let imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        EmptyView()
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// Designed artwork for catalog items that have no photo (yet). The first
// version dropped a 64pt emoji into a full-width gradient — it read as an
// empty block. This is a proper lockup on the same Theme gradient: soft
// decoration circles, the emoji in a frosted chip, then the product name and
// brand in the app's rounded display type. Used by PostCardView and
// SwipeCardView whenever product.image is nil.
public struct ProductArtworkView: View {
    public let post: Post

    public init(
        post: Post
    ) {
        self.post = post
    }


    public var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Color.gradient(for: post.product.grad)

                // Soft depth: two translucent circles, offset off the corners.
                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: side * 0.9)
                    .offset(x: -side * 0.38, y: -side * 0.42)
                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: side * 0.7)
                    .offset(x: side * 0.42, y: side * 0.40)

                VStack(spacing: side * 0.05) {
                    Text(post.product.emoji)
                        .font(.system(size: side * 0.18))
                        .frame(width: side * 0.32, height: side * 0.32)
                        .background(.white.opacity(0.55))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)

                    VStack(spacing: 6) {
                        Text(post.product.name)
                            .font(.system(size: max(17, side * 0.055), weight: .bold, design: .rounded))
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)

                        Text(post.isService
                             ? [post.product.brand, post.serviceDuration].compactMap { $0 }.joined(separator: " · ")
                             : post.product.brand)
                            .font(.captionMedium)
                            .fontWeight(.semibold)
                            .textCase(.uppercase)
                            .kerning(1.1)
                            .foregroundStyle(Color.ink.opacity(0.55))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, side * 0.12)
                }
            }
        }
    }
}

// Capsule tag for gift-able services ("a year of Netflix") — services often
// ship without a product photo, so the branded gradient + emoji IS the card
// and this badge is what tells the user it's a subscription, not a thing.
public struct ServiceBadge: View {
    public var duration: String?

    public init(
        duration: String? = nil
    ) {
        self.duration = duration
    }


    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gift.circle.fill")
                .font(.system(size: 11, weight: .bold))
            Text(duration.map { "Service · \($0)" } ?? "Service")
                .font(.system(size: 11, weight: .bold))
                .textCase(.uppercase)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.55))
        .clipShape(Capsule())
    }
}

public struct AvatarView: View {
    public let name: String
    public let grad: GradientStyle
    public var size: CGFloat = 40
    public var imageUrl: String? = nil
    public var anonymousFallback = false
    /// A merchant/brand domain. When there is no uploaded photo, the brand's own
    /// icon beats two letters — you recognise the Allbirds mark instantly and
    /// "AL" not at all.
    public var domain: String? = nil

    public init(
        name: String,
        grad: GradientStyle,
        size: CGFloat = 40,
        imageUrl: String? = nil,
        anonymousFallback: Bool = false,
        domain: String? = nil
    ) {
        self.name = name
        self.grad = grad
        self.size = size
        self.imageUrl = imageUrl
        self.anonymousFallback = anonymousFallback
        self.domain = domain
    }


    private var initials: String { AvatarPalette.initials(for: name) }

    // The photo, or the brand's icon, or nothing (initials show through).
    private var artworkURL: String? {
        imageUrl ?? AvatarPalette.brandIconURL(domain: domain)
    }

    public var body: some View {
        ZStack {
            // The fallback is ALWAYS drawn; the photo sits on top. A broken
            // avatar URL then reveals initials instead of a broken-photo icon.
            if anonymousFallback && artworkURL == nil { Color.surfaceSunken }
            // Hue is hashed from the name rather than picked from the small
            // GradientStyle enum, so two people are two colours instead of the
            // same muted olive.
            else { AvatarPalette.gradient(for: name) }

            if anonymousFallback && artworkURL == nil {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.52))
                    .foregroundStyle(Color.inkTertiary)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    // Two heavy letters on a mid-tone fill still soften at 24px;
                    // the shadow is what holds the edge.
                    .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            if let artworkURL {
                CachedAsyncImage(
                    url: artworkURL,
                    width: Int(size * 3),
                    showsFailurePlaceholder: false
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        // A 1px inner ring separates the avatar from the surface it sits on.
        // Without it, a dark-hued avatar melts into a dark background and the
        // circle stops reading as an object.
        .overlay {
            Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }
}


#endif
