import SwiftUI

// Post detail sheet — iOS port of the web PostModal (web/components/app/
// post-modal.tsx): full product image, seller row, price, caption, comments,
// and an outbound "View product" affiliate link.
struct PostDetailView: View {
    let post: Post
    var onLike: (() -> Void)?
    var onSave: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Product image
                    ZStack {
                        Color.gradient(for: post.product.grad)
                        Text(post.product.emoji)
                            .font(.system(size: 80))
                        if let image = post.product.image {
                            CachedAsyncImage(url: image, width: 900)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .clipped()

                    VStack(alignment: .leading, spacing: 12) {
                        // Poster row
                        HStack(spacing: 10) {
                            AvatarView(name: post.user, grad: post.product.grad, size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(post.user)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.ink)
                                Text(post.time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let source = post.source {
                                Text(source)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.cream)
                                    .clipShape(Capsule())
                            }
                        }

                        // Product name / brand / price
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(post.product.name)
                                    .font(.displaySmall)
                                    .foregroundStyle(Color.ink)
                                Text(post.product.brand)
                                    .font(.bodyMedium)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("$\(Int(post.product.price))")
                                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color.coral)
                                    .fixedSize()
                                if let was = post.product.was, was > post.product.price {
                                    Text("$\(Int(was))")
                                        .font(.caption)
                                        .strikethrough()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !post.caption.isEmpty {
                            Text(post.caption)
                                .font(.bodyLarge)
                                .foregroundStyle(Color.ink)
                        }

                        if let reason = post.reason {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12))
                                Text(reason)
                                    .font(.caption)
                            }
                            .foregroundStyle(Color.coral)
                        }

                        // Actions
                        HStack(spacing: 20) {
                            Button(action: { onLike?() }) {
                                Label("\(post.likes)", systemImage: post.liked ? "heart.fill" : "heart")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(post.liked ? Color.coral : Color.ink)
                            }
                            Button(action: { onSave?() }) {
                                Image(systemName: post.saved ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 18))
                                    .foregroundStyle(post.saved ? Color.coral : Color.ink)
                            }
                            if let shareUrl = Affiliate.productUrl(for: post) {
                                ShareLink(item: shareUrl) {
                                    Image(systemName: "paperplane")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Color.ink)
                                }
                            }
                            Spacer()
                        }
                        .padding(.top, 2)

                        // Outbound product link (affiliate-tagged)
                        if let url = Affiliate.productUrl(for: post) {
                            Button {
                                AnalyticsEngine.shared.trackAffiliateClick(
                                    postId: post.id,
                                    productUrl: url.absoluteString,
                                    source: "post_detail"
                                )
                                openURL(url)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "bag.fill")
                                    Text(Affiliate.isAmazonUrl(url.absoluteString) ? "View on Amazon" : "View product")
                                        .fixedSize()
                                }
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.coral)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .padding(.top, 6)
                        }

                        // Comments
                        if !post.comments.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Comments")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                ForEach(post.comments) { comment in
                                    HStack(alignment: .top, spacing: 8) {
                                        AvatarView(name: comment.user, grad: .peach, size: 26)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(comment.user)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(Color.ink)
                                            Text(comment.text)
                                                .font(.system(size: 13))
                                                .foregroundStyle(Color.ink)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.top, 10)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color.surface)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}
