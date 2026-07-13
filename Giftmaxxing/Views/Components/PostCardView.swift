import SwiftUI

struct PostCardView: View {
    let post: Post
    var inSwipeList: Bool = false
    var onPledge: (() -> Void)?
    var onAddToSwipeList: (() -> Void)?
    var onProductTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                AvatarView(name: post.user, grad: post.product.grad, size: 32)

                VStack(alignment: .leading, spacing: 1) {
                    Text(post.user)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    if let source = post.source {
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(post.time)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: {}) {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Product card
            Button(action: { onProductTap?() }) {
                ZStack {
                    Color.gradient(for: post.product.grad)

                    Text(post.product.emoji)
                        .font(.system(size: 64))

                    if let image = post.product.image {
                        CachedAsyncImage(url: image, width: 600)
                    }

                    // Services get a corner tag — same card, one subtle tell
                    // (a year of Netflix sits beside AirPods, on purpose).
                    if post.isService {
                        VStack {
                            HStack {
                                ServiceBadge(duration: post.serviceDuration)
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(12)
                    }

                    // Price badge
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 4) {
                                if let discount = post.product.discountPercent {
                                    Text("-\(discount)%")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.coral)
                                        .clipShape(Capsule())
                                }
                                Text("$\(Int(post.product.price))")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.6))
                                    .clipShape(Capsule())
                            }
                            .padding(12)
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .buttonStyle(.plain)

            // Gifting actions — no likes/comments/shares (this isn't
            // Instagram): start a pool for it, or queue it for a friend's
            // swipe list.
            HStack(spacing: 8) {
                Button(action: { onPledge?() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Pledge")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.coral)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: { onAddToSwipeList?() }) {
                    HStack(spacing: 5) {
                        Image(systemName: inSwipeList ? "checkmark" : "rectangle.stack.badge.plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text(inSwipeList ? "On swipe list" : "Add to swipe list")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(inSwipeList ? .white : Color.coral)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(inSwipeList ? Color.coral.opacity(0.75) : Color.coralSoft)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            // Caption — ONE flowing text run (an HStack of Texts squeezes the
            // username into its own truncating column once the caption wraps).
            if !post.caption.isEmpty {
                (Text(post.user).fontWeight(.semibold) + Text(" ") + Text(post.caption))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
            }

            // Recommendation reason — styled as a distinct "why you're seeing
            // this" note so it doesn't read as a second caption line.
            if let reason = post.reason, !reason.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text(reason)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(Color.coral.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.top, 4)
            }

            // Product info — name can be long; keep it to one truncated line and
            // let the brand hold its width so the row never wraps or collides.
            HStack(spacing: 6) {
                Text(post.product.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("·")
                Text(post.product.brand)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 5)
            .padding(.bottom, 14)
        }
        .background(Color.surface)
    }
}
