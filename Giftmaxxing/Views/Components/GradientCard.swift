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
