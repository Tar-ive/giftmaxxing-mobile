import AVKit
import SwiftUI

struct PostCardView: View {
    let post: Post
    var inSwipeList: Bool = false
    var inMyGiftIdeas: Bool = false
    var onLike: (() -> Void)?
    var onComment: (() -> Void)?
    var onBookmark: (() -> Void)?
    var onPledge: (() -> Void)?
    var onAddToSwipeList: (() -> Void)?
    var onProductTap: (() -> Void)?
    var onAuthorTap: (() -> Void)?
    var onHide: (() -> Void)?

    // Inline gallery position (Instagram-style paging right in the feed).
    @State private var galleryIndex = 0
    // Long-press reveals the gift's story — the alt-text of gifting.
    @State private var showStory = false
    @State private var showActions = false
    @State private var showReportReasons = false
    @State private var showVideo = false
    @State private var reportFeedback = 0
    @State private var musicPlayer: AVPlayer?
    @State private var isPlayingMusic = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Button { onAuthorTap?() } label: {
                    HStack(spacing: 10) {
                        AvatarView(
                            name: displayAuthor,
                            grad: post.product.grad,
                            size: 32,
                            imageUrl: post.authorImageUrl,
                            anonymousFallback: isUGC
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(displayAuthor)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ink)
                            if let retailer = retailerLabel {
                                Text(retailer).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!isUGC || post.ownerId == nil)

                Spacer()

                Text(post.time)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button { showActions = true } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Post options")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Product media — the carousel pages RIGHT IN THE FEED (no detour
            // through the detail sheet), Instagram-style. Tap opens detail,
            // long-press reveals the gift's story.
            ZStack {
                let gallery = post.product.gallery
                if gallery.count > 1 {
                    TabView(selection: $galleryIndex) {
                        ForEach(Array(gallery.enumerated()), id: \.offset) { idx, image in
                            ZStack {
                                Color.gradient(for: post.product.grad)
                                CachedAsyncImage(url: image, width: 600)
                            }
                            .clipped()
                            .tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .interactive))
                } else if let image = post.product.image {
                    Color.gradient(for: post.product.grad)
                    CachedAsyncImage(url: image, width: 600)
                } else {
                    // The designed brand lockup (catalog items pre-enrichment,
                    // services).
                    ProductArtworkView(post: post)
                }

                // Overlays ride ABOVE the pager so they persist across pages.
                VStack {
                    HStack(alignment: .top) {
                        // Services get a corner tag — same card, one subtle tell.
                        if post.isService {
                            ServiceBadge(duration: post.serviceDuration)
                        }
                        Spacer()
                        if post.product.gallery.count > 1 {
                            Text("\(galleryIndex + 1)/\(post.product.gallery.count)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.6))
                                .clipShape(Capsule())
                        }
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        // The story hint — hold to read (only when there IS one).
                        if GiftStory.story(for: post) != nil {
                            Image(systemName: "text.quote")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(.black.opacity(0.45))
                                .clipShape(Circle())
                                .accessibilityLabel("Hold to read this gift's story")
                        }
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
                            if !isUGC {
                                Text("$\(Int(post.product.price))")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.black.opacity(0.6))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(12)

                if isUGC, post.contentType == "ugc_video" {
                    Image(systemName: "play.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(ThemeSpacing.md)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                }

                // The story — alt-text for gifts. Long-press in, tap out.
                if showStory, let story = GiftStory.story(for: post) {
                    ZStack {
                        Color.black.opacity(0.72)
                        VStack(spacing: 10) {
                            Image(systemName: "text.quote")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.coral)
                            Text(story)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(9)
                            Text("Tap to close")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(24)
                    }
                    .transition(.opacity)
                }
            }
            // Instagram's 4:5 portrait — taller media, same edge-to-edge card.
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .contentShape(Rectangle())
            .onTapGesture {
                if showStory {
                    withAnimation(.easeOut(duration: 0.2)) { showStory = false }
                } else if isUGC, post.contentType == "ugc_video", post.mediaUrl != nil {
                    showVideo = true
                } else {
                    onProductTap?()
                }
            }
            .onLongPressGesture(minimumDuration: 0.35) {
                guard GiftStory.story(for: post) != nil else { return }
                withAnimation(.easeIn(duration: 0.2)) { showStory = true }
            }

            HStack(spacing: 15) {
                socialButton(
                    icon: post.liked ? "heart.fill" : "heart",
                    label: post.likes > 0 ? "\(post.likes)" : nil,
                    active: post.liked,
                    action: { onLike?() }
                )
                socialButton(
                    icon: "bubble.left",
                    label: post.displayCommentCount > 0 ? "\(post.displayCommentCount)" : nil,
                    action: { onComment?() }
                )
                if let shareURL {
                    ShareLink(
                        item: shareURL,
                        subject: Text("Gift find: \(post.product.name)"),
                        message: Text("Found this on Giftmaxxing — \(post.product.name)")
                    ) {
                        Image(systemName: "paperplane")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(Color.ink)
                    }
                    .accessibilityLabel("Share post")
                }
                socialButton(
                    icon: inMyGiftIdeas ? "bookmark.fill" : "bookmark",
                    active: inMyGiftIdeas,
                    action: { onBookmark?() }
                )
                Spacer(minLength: 4)
                giftAction(icon: "person.2.fill", label: "Pool", active: false) { onPledge?() }
                giftAction(
                    icon: inSwipeList ? "rectangle.stack.fill.badge.plus" : "rectangle.stack.badge.plus",
                    label: "Board",
                    active: inSwipeList
                ) { onAddToSwipeList?() }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            if let music = post.music {
                Button { toggleMusic(music) } label: {
                    Label(
                        "\(music.title) · \(music.artist)",
                        systemImage: isPlayingMusic ? "pause.fill" : "music.note"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }

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
        .confirmationDialog("Post options", isPresented: $showActions) {
            if isUGC, post.ownerId != AuthManager.shared.userId {
                Button("Report post", role: .destructive) { showReportReasons = true }
                if let ownerId = post.ownerId {
                    Button("Block this creator", role: .destructive) {
                        Task {
                            try? await APIClient.shared.blockUGCUser(userId: ownerId)
                            onHide?()
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Why are you reporting this?", isPresented: $showReportReasons) {
            ForEach(["Sexual content", "Violence", "Hate or harassment", "Spam", "Other"], id: \.self) { reason in
                Button(reason, role: .destructive) {
                    Task {
                        try? await APIClient.shared.reportUGCPost(postId: post.id, reason: reason)
                        reportFeedback += 1
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sensoryFeedback(.success, trigger: reportFeedback)
        .fullScreenCover(isPresented: $showVideo) {
            if let value = post.mediaUrl, let url = URL(string: value) {
                UGCVideoPlayerScreen(url: url)
            }
        }
        .onDisappear { musicPlayer?.pause() }
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

    private var displayAuthor: String {
        if isUGC { return post.user }
        let brand = post.product.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !brand.isEmpty, brand.lowercased() != "reddit" { return brand }
        return cleanedLabel(post.source ?? post.user)
    }

    private var retailerLabel: String? {
        if isUGC { return post.contentType == "ugc_video" ? "Video" : "Photo" }
        let source = post.source.map(cleanedLabel)
        guard let source, !source.isEmpty,
              source.caseInsensitiveCompare(displayAuthor) != .orderedSame else { return nil }
        return source
    }

    private var isUGC: Bool { post.source == "ugc" }

    private var shareURL: URL? {
        Affiliate.productUrl(for: post)
            ?? post.mediaUrl.flatMap(URL.init(string:))
            ?? post.posterUrl.flatMap(URL.init(string:))
    }

    private func toggleMusic(_ track: UGCMusicTrack) {
        if isPlayingMusic {
            musicPlayer?.pause()
            isPlayingMusic = false
            return
        }
        guard let url = URL(string: track.audioUrl) else { return }
        let player = musicPlayer ?? AVPlayer(url: url)
        musicPlayer = player
        player.play()
        isPlayingMusic = true
    }

    private func cleanedLabel(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
        if normalized.lowercased().hasPrefix("shopify ") {
            return String(normalized.dropFirst("shopify ".count))
        }
        return normalized
    }

    private func socialButton(
        icon: String,
        label: String? = nil,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                if let label { Text(label).font(.caption.weight(.semibold)) }
            }
            .foregroundStyle(active ? Color.coral : Color.ink)
        }
        .buttonStyle(.plain)
    }

    private func giftAction(icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(label).font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(active ? Color.coral : Color.ink)
            .frame(minWidth: 38, minHeight: 38)
            .background(active ? Color.coralSoft : Color.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct UGCVideoPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()
                .onAppear { player.play() }
                .onDisappear { player.pause() }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .padding(ThemeSpacing.md)
            .accessibilityLabel("Close video")
        }
    }
}
