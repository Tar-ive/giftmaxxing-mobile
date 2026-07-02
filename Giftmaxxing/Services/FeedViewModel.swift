import SwiftUI
import SwiftData

// Feed orchestration with the hybrid serving split:
//   server  = candidate generation only (GENERIC pages — no userId, so they are
//             CloudFront-cacheable and cost the same for 1 or 1M users)
//   device  = everything personal (seen de-dup, taste scoring, vector affinity,
//             diversity re-rank) via Services/Recommendation/.
// One 40-item network fetch feeds ~3 UI pages, and per-tap interaction writes
// are batched — both directly reduce Lambda invocations (the account's
// hard bottleneck, see docs/backend-scaling-design.md).
@MainActor
final class FeedViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?

    var userId: String?

    private var cursor: String?
    private var exhausted = false
    private let api = APIClient.shared

    // Ranked-but-not-yet-shown candidates (output of the on-device ranker).
    private var rankedBuffer: [RankedCandidate] = []
    private var servedIds = Set<String>()
    private var impressedIds = Set<String>()
    private var centroid: [Float]?

    private let networkPageSize = 40
    private let uiPageSize = 12

    // MARK: - Loading

    func loadFeed(context: ModelContext? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        cursor = nil
        exhausted = false
        rankedBuffer = []
        servedIds = []

        // Instant paint from the SwiftData cache while network + ranking run.
        if let context, posts.isEmpty {
            loadFromCache(context: context)
        }

        await refreshTasteCentroid()
        do {
            try await fetchAndRankNextPage()
            posts = drain(uiPageSize)
            if let context {
                cacheResults(posts, context: context)
            }
        } catch {
            if posts.isEmpty { self.error = error.localizedDescription }
        }

        isLoading = false
    }

    func loadMore(context: ModelContext? = nil) async {
        guard !isLoadingMore, !isLoading, !(exhausted && rankedBuffer.isEmpty) else { return }
        isLoadingMore = true

        if rankedBuffer.count < uiPageSize, !exhausted {
            try? await fetchAndRankNextPage()
        }
        posts.append(contentsOf: drain(uiPageSize))
        if let context {
            cacheResults(posts, context: context)
        }

        isLoadingMore = false
    }

    // One generic candidate fetch + full local ranking pass.
    private func fetchAndRankNextPage() async throws {
        let page = try await api.fetchFeed(cursor: cursor, limit: networkPageSize)
        cursor = page.cursor
        if page.cursor == nil || page.posts.isEmpty { exhausted = true }

        let profile = await TasteProfileStore.shared.snapshot()
        let similarities = await vectorSimilarities(for: page.posts)

        let fresh = page.posts.filter { !servedIds.contains($0.id) }
        let ranked = OnDeviceRanker.rank(
            candidates: fresh,
            profile: profile,
            centroid: centroid,
            vectorSimilarities: similarities
        )
        rankedBuffer.append(contentsOf: ranked)
        // Re-sort across network pages so a strong late arrival can outrank a
        // weak leftover, then re-apply nothing else (diversity was per-page).
        rankedBuffer.sort { $0.score > $1.score }
    }

    private func drain(_ n: Int) -> [Post] {
        let batch = rankedBuffer.prefix(n)
        rankedBuffer.removeFirst(batch.count)
        return batch.map { candidate in
            servedIds.insert(candidate.post.id)
            var post = candidate.post
            if post.reason == nil { post.reason = candidate.reason }
            return post
        }
    }

    // MARK: - Vector affinity (Titan space, cached locally)

    // Build/refresh the taste centroid from the user's seed items. All math is
    // on-device (vDSP); the network is touched only for vectors not yet cached.
    private func refreshTasteCentroid() async {
        let profile = await TasteProfileStore.shared.snapshot()
        guard profile.seedKeys.count >= 3 else { return }
        await ensureVectorsCached(keys: profile.seedKeys)
        centroid = await VectorStore.shared.centroid(of: profile.seedKeys)
    }

    private func vectorSimilarities(for candidates: [Post]) async -> [String: Float] {
        guard let centroid else { return [:] }
        let keys = candidates.map(\.id)
        await ensureVectorsCached(keys: keys)
        return await VectorStore.shared.similarities(keys: keys, to: centroid)
    }

    private func ensureVectorsCached(keys: [String]) async {
        let missing = await VectorStore.shared.missingKeys(from: keys)
        guard !missing.isEmpty else { return }
        guard let response = try? await api.fetchVectors(keys: missing) else { return }
        for item in response.items ?? [] {
            await VectorStore.shared.upsert(key: item.key, base64: item.data, scale: item.scale)
        }
    }

    // MARK: - Interactions (instant local signal + batched upload)

    func recordImpression(for post: Post) {
        guard !impressedIds.contains(post.id) else { return }
        impressedIds.insert(post.id)
        Task {
            await TasteProfileStore.shared.record(tasteEvent(.impression, post))
            // Impressions stay device-only (they exist for de-dup + taste decay);
            // uploading them would just buy DynamoDB writes for no ranking gain.
        }
    }

    func recordOpen(for post: Post) {
        Task {
            await TasteProfileStore.shared.record(tasteEvent(.open, post))
            await InteractionQueue.shared.enqueue(userId: userId, targetId: post.id, type: "open")
        }
    }

    func toggleLike(for post: Post, context: ModelContext? = nil) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[index].liked.toggle()
        posts[index].likes += posts[index].liked ? 1 : -1
        let liked = posts[index].liked

        // SwiftData cache keeps the UI state consistent across launches; the
        // server write goes through the batched InteractionQueue (one Lambda
        // invocation per ~10 taps instead of one per tap).
        if let context {
            updateCache(postId: post.id, liked: liked, likes: posts[index].likes, context: context)
        }
        Task {
            await TasteProfileStore.shared.record(tasteEvent(liked ? .like : .unlike, post))
            await InteractionQueue.shared.enqueue(userId: userId, targetId: post.id, type: liked ? "like" : "unlike")
            if liked { await seedVector(for: post) }
        }
    }

    func toggleSave(for post: Post, context: ModelContext? = nil) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[index].saved.toggle()
        let saved = posts[index].saved

        if let context {
            updateCache(postId: post.id, saved: saved, context: context)
        }
        Task {
            await TasteProfileStore.shared.record(tasteEvent(saved ? .save : .unsave, post))
            await InteractionQueue.shared.enqueue(userId: userId, targetId: post.id, type: saved ? "save" : "unsave")
            if saved { await seedVector(for: post) }
        }
    }

    private func loadFromCache(context: ModelContext) {
        let descriptor = FetchDescriptor<CachedPost>(
            sortBy: [SortDescriptor(\.feedPosition)]
        )
        if let cached = try? context.fetch(descriptor), !cached.isEmpty {
            posts = cached.map { $0.toPost() }
        }
    }

    private func cacheResults(_ posts: [Post], context: ModelContext) {
        try? context.delete(model: CachedPost.self)
        for (index, post) in posts.enumerated() {
            let cached = CachedPost(from: post, position: index)
            context.insert(cached)
        }
        try? context.save()
    }

    private func updateCache(postId: String, liked: Bool? = nil, likes: Int? = nil, saved: Bool? = nil, context: ModelContext) {
        let descriptor = FetchDescriptor<CachedPost>(
            predicate: #Predicate { $0.postId == postId }
        )
        guard let cached = try? context.fetch(descriptor).first else { return }
        if let liked { cached.liked = liked }
        if let likes { cached.likes = likes }
        if let saved { cached.saved = saved }
        try? context.save()
    }

    func prefetchImages(around index: Int) {
        guard !posts.isEmpty else { return }
        let range = max(0, index - 2)...min(posts.count - 1, index + 5)
        let urls = posts[range].compactMap { $0.product.image }
        Task {
            await ImageLoader.shared.prefetch(urls: urls, width: 600)
        }
    }

    func flushInteractions() {
        Task { await InteractionQueue.shared.flush() }
    }

    // A new strong signal reshapes taste immediately: cache its vector and
    // recompute the centroid so the NEXT page is already smarter.
    private func seedVector(for post: Post) async {
        await ensureVectorsCached(keys: [post.id])
        await refreshTasteCentroid()
    }

    private func tasteEvent(_ kind: TasteEvent.Kind, _ post: Post) -> TasteEvent {
        let signals = TasteSignals.extract(from: post)
        return TasteEvent(
            kind: kind,
            postId: post.id,
            author: post.user,
            price: post.product.price,
            vibes: signals.vibes,
            category: signals.category
        )
    }
}
