import SwiftUI

struct GradientCard: View {
    let grad: GradientStyle
    let emoji: String
    var imageURL: String?
    var size: CGFloat = 120

    var body: some View {
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
struct ProductArtworkView: View {
    let post: Post

    var body: some View {
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
                            .font(.caption)
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
struct ServiceBadge: View {
    var duration: String?

    var body: some View {
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

struct AvatarView: View {
    let name: String
    let grad: GradientStyle
    var size: CGFloat = 40

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))"
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        ZStack {
            Color.gradient(for: grad)
            Text(initials)
                .font(.system(size: size * 0.35, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
