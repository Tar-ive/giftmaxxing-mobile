import SwiftUI
import GiftmaxxingCore

// Loads every idea pack once and shares it between the Home rail and the
// see-all screen, so opening "See all" is instant rather than a second fan-out
// of the same requests.
//
// Galleries come from CONFIG gallery#<id> rows (server-curated by semantic
// kNN); bundles from CONFIG bundles#<recipient> rows (Reddit co-occurrence,
// plus the hand-authored age bands). Both are already-cached GETs, so this is
// cheap — but it is still one request per gallery, hence the shared cache.
@MainActor
final class IdeasLoader: ObservableObject {
    static let shared = IdeasLoader()

    @Published private(set) var packs: [IdeaPack] = []
    @Published private(set) var isLoading = false

    private var loaded = false

    private init() {}

    /// Rail-friendly ordering: alternate gallery / bundle so the first screen
    /// shows both kinds instead of eight shelves then eight bundles.
    var interleaved: [IdeaPack] {
        let galleries = packs.filter { $0.kind == .gallery }
        let bundles = packs.filter { $0.kind == .bundle }
        var out: [IdeaPack] = []
        for index in 0..<max(galleries.count, bundles.count) {
            if index < galleries.count { out.append(galleries[index]) }
            if index < bundles.count { out.append(bundles[index]) }
        }
        return out
    }

    func loadIfNeeded() async {
        guard !loaded, !isLoading else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false; loaded = true }

        async let galleries = loadGalleries()
        async let bundles = loadBundles()
        packs = await galleries + (await bundles)
    }

    private func loadGalleries() async -> [IdeaPack] {
        await withTaskGroup(of: (Int, IdeaPack?).self) { group in
            for (index, collection) in CuratedCollection.all.enumerated() {
                group.addTask {
                    let items = await Self.items(for: collection)
                    guard !items.isEmpty else { return (index, nil) }
                    return (index, IdeaPack.from(collection, items: items))
                }
            }
            // Preserve the curated order from CuratedCollection.all rather than
            // whatever finishes first.
            var byIndex: [Int: IdeaPack] = [:]
            for await (index, pack) in group {
                if let pack { byIndex[index] = pack }
            }
            return byIndex.sorted { $0.key < $1.key }.map(\.value)
        }
    }

    // Prefer the server-curated member list (semantic kNN over the shelf's
    // theme, build-shelves.mjs). The vibe query is the fallback for shelves
    // that haven't been curated yet — vibe tags are store-level and noisy, so
    // it's a last resort, not a peer.
    private static func items(for collection: CuratedCollection) async -> [Post] {
        if let curated = try? await APIClient.shared.fetchGallery(id: collection.id, limit: 24),
           curated.count >= 8 {
            let filtered = filter(curated, for: collection)
            if filtered.count >= 8 { return filtered }
        }

        guard let page = try? await APIClient.shared.fetchFeed(
            limit: 40,
            vibes: collection.vibes.isEmpty ? nil : collection.vibes,
            recipient: collection.recipient,
            occasion: collection.occasion,
            category: collection.category,
            budget: collection.maxPrice
        ) else { return [] }
        return filter(page.posts, for: collection)
    }

    // Enforce the "Under $X" promise client-side — the server budget hint is a
    // soft bias — and require a real photo, since a shelf is sold on its images.
    private static func filter(_ posts: [Post], for collection: CuratedCollection) -> [Post] {
        var seen = Set<String>()
        return posts.filter { post in
            guard seen.insert(post.id).inserted else { return false }
            if let cap = collection.maxPrice, post.product.price > 0, post.product.price > cap {
                return false
            }
            return post.product.image != nil
        }
    }

    private func loadBundles() async -> [IdeaPack] {
        let bundles = (try? await APIClient.shared.fetchGiftBundles(limit: 12)) ?? []
        return bundles
            .map(IdeaPack.from)
            // A bundle with a single slot isn't a pairing — drop it.
            .filter { $0.sections.count >= 2 }
    }
}
