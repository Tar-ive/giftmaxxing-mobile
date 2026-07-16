import SwiftUI

// A curated gallery opened: a themed shelf of real catalog products, filtered
// to the collection's promise (price cap, vibe, category). Two-column grid;
// tapping a product opens the full detail sheet with all the usual actions
// (save to a Gift Board, gift pool, buy).
struct CollectionDetailView: View {
    let collection: CuratedCollection

    @State private var posts: [Post] = []
    @State private var isLoading = true
    @State private var selectedPost: Post?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if posts.isEmpty {
                    VStack(spacing: 10) {
                        Text(collection.emoji).font(.system(size: 44))
                        Text("Fresh picks for this gallery are on the way.")
                            .font(.bodyMedium)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(posts) { post in
                            Button { selectedPost = post } label: {
                                productCard(post)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.cream)
        .navigationTitle(collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $selectedPost) { post in
            PostDetailView(post: post)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(collection.emoji).font(.system(size: 30))
                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.title)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.ink)
                    Text(collection.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
    }

    private func productCard(_ post: Post) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Color.gradient(for: post.product.grad)
                    if let image = post.product.image {
                        CachedAsyncImage(url: image, width: 400)
                    } else {
                        Text(post.product.emoji).font(.system(size: 34))
                    }
                }
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if post.product.gallery.count > 1 {
                    Image(systemName: "square.stack.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.black.opacity(0.35), in: Circle())
                        .padding(8)
                }
            }

            Text(post.product.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if post.product.price > 0 {
                Text("$\(Int(post.product.price))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.coral)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        // Prefer the server-curated member list (semantic curation, see
        // build-shelves.mjs) — the legacy vibe-query below is the fallback
        // for shelves that haven't been curated yet.
        if let curated = try? await APIClient.shared.fetchGallery(id: collection.id),
           curated.count >= 8 {
            var seen = Set<String>()
            posts = curated.filter { post in
                guard seen.insert(post.id).inserted else { return false }
                if let cap = collection.maxPrice, post.product.price > 0, post.product.price > cap { return false }
                return post.product.image != nil
            }
            if posts.count >= 8 { return }
        }

        guard let page = try? await APIClient.shared.fetchFeed(
            limit: 40,
            vibes: collection.vibes.isEmpty ? nil : collection.vibes,
            recipient: collection.recipient,
            occasion: collection.occasion,
            category: collection.category,
            budget: collection.maxPrice
        ) else { return }

        // Enforce the "Under $X" promise client-side (the server budget hint is
        // a soft bias). Prefer real photos, and de-dup.
        var seen = Set<String>()
        posts = page.posts.filter { post in
            guard seen.insert(post.id).inserted else { return false }
            if let cap = collection.maxPrice, post.product.price > 0, post.product.price > cap { return false }
            return post.product.image != nil
        }
    }
}
