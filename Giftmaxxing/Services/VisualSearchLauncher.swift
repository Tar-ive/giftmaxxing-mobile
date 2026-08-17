import SwiftUI
import UIKit
import GiftmaxxingCore
import GiftmaxxingNetworking
import GiftmaxxingDesignSystem

// "Where can I buy THAT?" — run visual search from an image the app already
// has (a UGC photo, a video's poster frame) instead of only from the camera.
// The server takes base64, so the image is fetched through the existing cache
// and downscaled before it's sent.
enum VisualSearchLauncher {
    /// Downscaled base64 for /visual-search, or nil if the image can't load.
    static func payload(for imageUrl: String?) async -> String? {
        guard let imageUrl, !imageUrl.isEmpty,
              let image = await ImageLoader.shared.load(url: imageUrl, width: 800)
        else { return nil }
        return image
            .resized(maxDimension: 512)
            .jpegData(compressionQuality: 0.8)?
            .base64EncodedString()
    }

    /// Hand the image to the full visual-search screen (same surface the
    /// camera and share-extension captures use).
    @MainActor
    static func open(imageUrl: String?, in appState: AppState) async {
        guard let imageUrl, !imageUrl.isEmpty,
              let image = await ImageLoader.shared.load(url: imageUrl, width: 800)
        else { return }
        appState.pendingCaptureImage = image
        appState.pendingCaptureNote = nil
        appState.openSearch(.visual)
    }
}

// Shoppable matches for a post's photo — the "buy it" answer under a UGC find,
// resolved by embedding the photo and kNN-ing the catalog (same path as camera
// visual search). Hidden entirely when nothing matches closely enough.
struct ShopThisPostRail: View {
    /// Server-cached matches are keyed by post; without an id we fall back to
    /// embedding the image on demand.
    var postId: String? = nil
    let imageUrl: String?
    let caption: String?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager

    @State private var matches: [VectorItem] = []
    @State private var isLoading = true
    @State private var selected: VectorItem?

    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Finding where to buy…")
                        .font(.captionMedium)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            } else if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Shop this look", systemImage: "bag.fill")
                            .font(.labelBold)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Button("See all") {
                            Task { await VisualSearchLauncher.open(imageUrl: imageUrl, in: appState) }
                        }
                        .font(.bodySmall.weight(.semibold))
                        .foregroundStyle(Color.coral)
                    }
                    .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(matches) { match in
                                Button { selected = match } label: { card(match) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .task { await load() }
        // Straight to the merchant — this rail's whole job is "buy it".
        .sheet(item: $selected) { item in
            if let link = item.productUrl ?? item.url, let url = URL(string: link) {
                SafariView(url: url)
            }
        }
    }

    private func card(_ post: VectorItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Color.surfaceSunken
                if let image = post.image {
                    CachedAsyncImage(url: image, width: 300)
                }
            }
            .frame(width: 116, height: 116)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous))

            Text(post.name ?? "Gift idea")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let price = post.price, price > 0 {
                Text(price, format: .currency(code: "USD"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.coral)
            } else if let merchant = post.merchant {
                Text(merchant)
                    .font(.captionMedium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 116, alignment: .leading)
    }

    private func load() async {
        defer { isLoading = false }
        // Server-side, computed once and cached on the post.
        if let postId {
            // A post-scoped response is authoritative, including an empty one.
            // Falling through to a loose visual search here was the source of
            // unrelated "Shop this look" products.
            matches = (try? await APIClient.shared.fetchShoppable(postId: postId)) ?? []
            return
        }
        guard let base64 = await VisualSearchLauncher.payload(for: imageUrl) else { return }
        let response = try? await APIClient.shared.fetchVisualSearch(
            imageBase64: base64,
            text: caption,
            limit: 10,
            userId: authManager.userId
        )
        matches = response?.items ?? []
    }
}
