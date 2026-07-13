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
                    // Photo when we have one; the designed brand lockup when we
                    // don't (catalog items pre-enrichment, services).
                    if let image = post.product.image {
                        Color.gradient(for: post.product.grad)
                        CachedAsyncImage(url: image, width: 600)
                    } else {
                        ProductArtworkView(post: post)
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
            // Instagram): start a gift pool with friends, or file it into a
            // person's swipe list. Two matched half-width buttons — same
            // height, same type — so the row reads as one control.
            HStack(spacing: 8) {
                actionButton(
                    icon: "person.2.fill",
                    label: "Gift pool",
                    prominent: true,
                    action: { onPledge?() }
                )
                actionButton(
                    icon: inSwipeList ? "checkmark" : "rectangle.stack.badge.plus",
                    label: inSwipeList ? "On swipe list" : "Swipe list",
                    prominent: false,
                    action: { onAddToSwipeList?() }
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            // Product info — ONE title + ONE meta line. The old stack (caption
            // run + reason note + name·brand row) printed the same SEO title
            // three times per card; the header already names the source.
            VStack(alignment: .leading, spacing: 3) {
                Text(post.product.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let reason = distinctReason {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                        Text(reason)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(Color.coral.opacity(0.9))
                } else {
                    Text(post.product.brand)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .background(Color.surface)
    }

    // A reason worth a line of its own ("Similar to your taste"). Merchant
    // echoes ("Real find from ebay.com") duplicate the brand line — drop them.
    private var distinctReason: String? {
        guard let reason = post.reason, !reason.isEmpty else { return nil }
        let lower = reason.lowercased()
        let brand = post.product.brand.lowercased()
        if !brand.isEmpty, lower.contains(brand) { return nil }
        if let domain = post.domain?.lowercased(), !domain.isEmpty, lower.contains(domain) { return nil }
        return reason
    }

    private func actionButton(
        icon: String,
        label: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(prominent ? .white : Color.coral)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(prominent ? Color.coral : Color.coralSoft)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
