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
    // Save the find into a person's swipe list — reachable from anywhere this
    // sheet opens (feed, search, visual search results).
    @State private var showListPicker = false
    @ObservedObject private var swipeLists = SwipeListStore.shared
    // Carousel position for the "n/N" counter; resets when the sheet swaps to
    // a similar product in place.
    @State private var galleryIndex = 0
    // User uploads render at their real shape (vertical or square); products
    // keep the editorial 4:5 crop.
    @State private var measuredAspect: CGFloat?

    private var detailAspectRatio: CGFloat {
        if activePost.contentType == "ugc_video" { return MediaAspect.vertical }
        if CuratedGiftStore.shared.journey(containing: activePost.id) != nil
            || activePost.source == "curated-product" {
            return MediaAspect.recommendationCard
        }
        // Personal UGC keeps its authored shape. Catalog recommendations keep
        // the same portrait contract as the two-column discovery card.
        if let real = activePost.aspectRatio, real > 0.2, real < 3 {
            return CGFloat(real)
        }
        if activePost.source == "ugc", let measured = measuredAspect {
            return MediaAspect.snap(measured)
        }
        return activePost.source == "ugc" ? MediaAspect.square : MediaAspect.recommendationCard
    }
    @State private var comments: [Comment] = []
    @State private var commentDraft = ""
    @State private var sendingComment = false

    // The sheet can swap to a similar product in place (swipe-right-for-similar).
    private var activePost: Post { displayedPost ?? post }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Product images — Instagram-style: 4:5 portrait media, a
                    // swipeable carousel with an "n/N" counter when the listing
                    // carries a gallery, the single cover otherwise.
                    Group {
                        let gallery = activePost.product.gallery
                        if gallery.count > 1 {
                            ZStack(alignment: .topTrailing) {
                                TabView(selection: $galleryIndex) {
                                    ForEach(Array(gallery.enumerated()), id: \.offset) { idx, image in
                                        ZStack {
                                            Color.gradient(for: activePost.product.grad)
                                            CachedAsyncImage(url: image, width: 900)
                                        }
                                        .clipped()
                                        .tag(idx)
                                    }
                                }
                                .tabViewStyle(.page(indexDisplayMode: .always))
                                .indexViewStyle(.page(backgroundDisplayMode: .interactive))

                                Text("\(galleryIndex + 1)/\(gallery.count)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.black.opacity(0.6))
                                    .clipShape(Capsule())
                                    .padding(12)
                            }
                        } else {
                            ZStack {
                                Color.gradient(for: activePost.product.grad)
                                Text(activePost.product.emoji)
                                    .font(.system(size: 80))
                                if let image = gallery.first {
                                    CachedAsyncImage(url: image, width: 900) { ratio in
                                        // Measure EVERY post, not just UGC.
                                        // It is the fallback for anything whose
                                        // source didn't ship dimensions, and
                                        // gating it on ugc left every scraped
                                        // image stuck on the 4:5 default.
                                        if measuredAspect == nil { measuredAspect = ratio }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(detailAspectRatio, contentMode: .fit)
                    .clipped()

                    // UGC has no product attached — reverse-image search turns
                    // "love that" into something you can actually buy.
                    if activePost.source == "ugc",
                       CuratedGiftStore.shared.journey(containing: activePost.id) == nil {
                        ShopThisPostRail(
                            postId: activePost.id,
                            imageUrl: activePost.product.gallery.first ?? activePost.product.image,
                            caption: activePost.caption
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        // Poster row
                        HStack(spacing: 10) {
                            AvatarView(
                                name: activePost.user,
                                grad: activePost.product.grad,
                                size: 36,
                                imageUrl: activePost.authorImageUrl,
                                anonymousFallback: activePost.source == "ugc"
                            )
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

                        // The story behind the gift — maker's note, anecdote,
                        // provenance (same text the feed shows on long-press).
                        if let story = GiftStory.story(for: activePost) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 5) {
                                    Image(systemName: "text.quote")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("THE STORY")
                                        .font(.system(size: 11, weight: .bold))
                                        .tracking(0.5)
                                }
                                .foregroundStyle(Color.coral)
                                Text(story)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.ink)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Actions
                        HStack(spacing: 20) {
                            Button(action: { onLike?() }) {
                                Label("\(activePost.likes)", systemImage: activePost.liked ? "heart.fill" : "heart")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(activePost.liked ? Color.coral : Color.ink)
                            }
                            Button {
                                if let onSave { onSave() }
                                else { swipeLists.toggleMyGiftIdea(activePost) }
                            } label: {
                                Image(systemName: (activePost.saved || swipeLists.containsInMyGiftIdeas(activePost)) ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 18))
                                    .foregroundStyle((activePost.saved || swipeLists.containsInMyGiftIdeas(activePost)) ? Color.coral : Color.ink)
                            }
                            Button(action: { showListPicker = true }) {
                                Image(systemName: swipeLists.contains(activePost)
                                      ? "rectangle.stack.fill.badge.plus"
                                      : "rectangle.stack.badge.plus")
                                    .font(.system(size: 18))
                                    .foregroundStyle(swipeLists.contains(activePost) ? Color.coral : Color.ink)
                            }
                            .accessibilityLabel("Add to a Gift Board")
                            if let shareUrl = shareURL(for: activePost) {
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

                        // Major-retailer fallbacks — the organic link often
                        // points at a niche shop (Etsy/eBay/Pinterest source);
                        // these one-tap searches put the same product on the
                        // stores US shoppers actually buy from.
                        let retailerLinks = Affiliate.retailerSearchLinks(for: activePost)
                        if !retailerLinks.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Find it at")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                HStack(spacing: 8) {
                                    ForEach(retailerLinks) { link in
                                        Button {
                                            OutboundRouter.open(link.url, postId: activePost.id, source: "retailer_search") {
                                                browserTarget = BrowserTarget(url: $0)
                                            }
                                        } label: {
                                            HStack(spacing: 5) {
                                                Image(systemName: "magnifyingglass")
                                                    .font(.system(size: 11, weight: .semibold))
                                                Text(link.name)
                                                    .font(.system(size: 13, weight: .bold))
                                            }
                                            .foregroundStyle(Color.ink)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 9)
                                            .background(Color.cream)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            .padding(.top, 8)
                        }

                        // Similar gifts — swipeable rail (vector kNN seeded by
                        // this product, category fallback when offline).
                        if !similar.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(CuratedGiftStore.shared.journey(containing: activePost.id) == nil
                                     ? "Closely related gifts" : "Products in this post")
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
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Community")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            ForEach(comments) { comment in
                                HStack(alignment: .top, spacing: 8) {
                                    AvatarView(
                                        name: comment.user,
                                        grad: .peach,
                                        size: 26,
                                        imageUrl: comment.authorImageUrl,
                                        anonymousFallback: true
                                    )
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
                            if comments.isEmpty {
                                Text("No comments yet. Be the first to share what you think.")
                                    .font(.bodySmall)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                TextField("Add a comment…", text: $commentDraft, axis: .vertical)
                                    .lineLimit(1...3)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(Color.cream)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                Button { Task { await sendComment() } } label: {
                                    if sendingComment { ProgressView().tint(Color.coral) }
                                    else { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                                }
                                .foregroundStyle(Color.coral)
                                .disabled(sendingComment || commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityLabel("Post comment")
                            }
                        }
                        .padding(.top, 10)
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
            .sheet(isPresented: $showListPicker) {
                SwipeListPickerSheet(post: activePost)
            }
            .task {
                await loadSimilar(for: post)
                await loadComments(for: post)
            }
            .onChange(of: activePost.id) { _, _ in
                galleryIndex = 0
                Task { await loadComments(for: activePost) }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func shareURL(for post: Post) -> URL? {
        Affiliate.productUrl(for: post)
            ?? post.mediaUrl.flatMap(URL.init(string:))
            ?? post.posterUrl.flatMap(URL.init(string:))
    }

    private func loadComments(for post: Post) async {
        comments = post.comments
        if let response = try? await APIClient.shared.fetchPostComments(postId: post.id) {
            comments = response.items
        }
    }

    private func sendComment() async {
        let text = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sendingComment = true
        defer { sendingComment = false }
        if let response = try? await APIClient.shared.addPostComment(postId: activePost.id, text: text) {
            comments.append(response.item)
            commentDraft = ""
            AnalyticsEngine.shared.trackContentAction(.contentComment, postId: activePost.id, source: "post_detail")
            await InteractionQueue.shared.enqueue(
                userId: AuthManager.shared.userId,
                targetId: activePost.id,
                type: "comment"
            )
        }
    }

    private func loadSimilar(for seed: Post) async {
        if let journey = CuratedGiftStore.shared.journey(containing: seed.id) {
            similar = CuratedGiftStore.shared.products(for: journey)
                .map(\.post)
                .filter { $0.id != seed.id }
            return
        }
        guard seed.source != "ugc" else {
            similar = []
            return
        }
        let api = APIClient.shared

        if let response = try? await api.fetchVectorRecommendations(seedKeys: [seed.id], limit: 10),
           let items = response.items, !items.isEmpty {
            similar = items
                .filter { item in
                    guard item.postId != seed.id,
                          item.image != nil,
                          item.productUrl != nil || item.url != nil else { return false }
                    let seedTerms = semanticTerms(seed.product.name + " " + seed.product.brand)
                    let itemTerms = semanticTerms((item.name ?? "") + " " + (item.merchant ?? ""))
                    return !seedTerms.isDisjoint(with: itemTerms)
                }
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
        similar = []
    }

    private func semanticTerms(_ value: String) -> Set<String> {
        Set(value.lowercased().split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 4 && !["with", "from", "gift", "idea"].contains($0) })
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
