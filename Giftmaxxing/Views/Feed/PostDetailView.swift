import SwiftUI

// Post detail sheet — iOS port of the web PostModal (web/components/app/
// post-modal.tsx): full product image, seller row, price, caption, comments,
// and an outbound "View product" affiliate link.
struct PostDetailView: View {
    let post: Post
    var onLike: (() -> Void)?
    var onSave: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var browserTarget: BrowserTarget?
    @State private var similar: [Post] = []
    @State private var displayedPost: Post?

    // The sheet can swap to a similar product in place (swipe-right-for-similar).
    private var activePost: Post { displayedPost ?? post }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Product image
                    ZStack {
                        Color.gradient(for: activePost.product.grad)
                        Text(activePost.product.emoji)
                            .font(.system(size: 80))
                        if let image = activePost.product.image {
                            CachedAsyncImage(url: image, width: 900)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .clipped()

                    VStack(alignment: .leading, spacing: 12) {
                        // Poster row
                        HStack(spacing: 10) {
                            AvatarView(name: activePost.user, grad: activePost.product.grad, size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(activePost.user)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.ink)
                                Text(activePost.time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let source = activePost.source {
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
                                Text(activePost.product.name)
                                    .font(.displaySmall)
                                    .foregroundStyle(Color.ink)
                                Text(activePost.product.brand)
                                    .font(.bodyMedium)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("$\(Int(activePost.product.price))")
                                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Color.coral)
                                    .fixedSize()
                                if let was = activePost.product.was, was > activePost.product.price {
                                    Text("$\(Int(was))")
                                        .font(.caption)
                                        .strikethrough()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !activePost.caption.isEmpty {
                            Text(activePost.caption)
                                .font(.bodyLarge)
                                .foregroundStyle(Color.ink)
                        }

                        if let reason = activePost.reason {
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
                                Label("\(activePost.likes)", systemImage: activePost.liked ? "heart.fill" : "heart")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(activePost.liked ? Color.coral : Color.ink)
                            }
                            Button(action: { onSave?() }) {
                                Image(systemName: activePost.saved ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 18))
                                    .foregroundStyle(activePost.saved ? Color.coral : Color.ink)
                            }
                            if let shareUrl = Affiliate.productUrl(for: activePost) {
                                // Share a friendly message, not a bare URL (bare
                                // retailer URLs make the share sheet surface odd
                                // suggestions like birthday reminders).
                                ShareLink(
                                    item: shareUrl,
                                    subject: Text("Gift idea: \(activePost.product.name)"),
                                    message: Text("Found this on Giftmaxxing \u{2014} \(activePost.product.name) ($\(Int(activePost.product.price)))")
                                ) {
                                    Image(systemName: "paperplane")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Color.ink)
                                }
                            }
                            Spacer()
                        }
                        .padding(.top, 2)

                        // Outbound product link — Amazon app via universal link
                        // when installed, in-app browser otherwise.
                        if let url = Affiliate.productUrl(for: activePost) {
                            Button {
                                OutboundRouter.open(url, postId: activePost.id, source: "post_detail") {
                                    browserTarget = BrowserTarget(url: $0)
                                }
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

                        // Similar gifts — swipeable rail (vector kNN seeded by
                        // this product, category fallback when offline).
                        if !similar.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Similar gifts")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(similar) { item in
                                            Button {
                                                displayedPost = item
                                                Task { await loadSimilar(for: item) }
                                            } label: {
                                                SimilarProductTile(post: item)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 10)
                        }

                        // Comments
                        if !activePost.comments.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Comments")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                ForEach(activePost.comments) { comment in
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
            .sheet(item: $browserTarget) { target in
                SafariView(url: target.url)
                    .ignoresSafeArea()
            }
            .task {
                await loadSimilar(for: post)
            }
        }
        .presentationDragIndicator(.visible)
    }

    // Vector recs seeded by the product (same kNN the web uses); falls back
    // to same-category posts from the feed when the vector path is empty.
    private func loadSimilar(for seed: Post) async {
        let api = APIClient.shared

        if let response = try? await api.fetchVectorRecommendations(seedKeys: [seed.id], limit: 10),
           let items = response.items, !items.isEmpty {
            similar = items
                .filter { $0.postId != seed.id }
                .map { item in
                    Post(
                        id: item.postId,
                        user: item.author ?? "giftmaxxing",
                        time: "",
                        product: Product(
                            id: item.postId,
                            name: item.name ?? "Gift idea",
                            brand: item.merchant ?? item.source ?? "",
                            price: item.price ?? 0,
                            grad: .coral,
                            emoji: "\u{1F381}",
                            image: item.image
                        ),
                        caption: item.reason ?? "",
                        likes: 0,
                        productUrl: item.productUrl ?? item.url
                    )
                }
            return
        }

        // Fallback: same-category picks from the feed.
        if let page = try? await api.fetchFeed(limit: 30, category: seed.category) {
            similar = page.posts.filter { $0.id != seed.id }.prefix(10).map { $0 }
        }
    }
}

private struct SimilarProductTile: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                Color.gradient(for: post.product.grad)
                Text(post.product.emoji).font(.system(size: 28))
                if let image = post.product.image {
                    CachedAsyncImage(url: image, width: 300)
                }
            }
            .frame(width: 110, height: 110)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(post.product.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)

            if post.product.price > 0 {
                Text("$\(Int(post.product.price))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.coral)
            }
        }
    }
}
