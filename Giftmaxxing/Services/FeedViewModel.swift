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
    // Unique per pull-to-refresh; nil for normal (CDN-cacheable) loads.
    private var cacheBuster: String?
    private let api = APIClient.shared

    // Ranked-but-not-yet-shown candidates (output of the on-device ranker).
    private var rankedBuffer: [RankedCandidate] = []
    private var servedIds = Set<String>()
    private var impressedIds = Set<String>()
    private var dwelledIds = Set<String>()
    private var centroid: [Float]?
    // Anti-centroid over explicitly hidden items — hides never leave the
    // device, but candidates similar to them still sink in ranking.
    private var negCentroid: [Float]?

    private let networkPageSize = 40
    private let uiPageSize = 12

    // MARK: - Loading

    // forceFresh = pull-to-refresh: bust the CDN cache so the server deals a
    // brand-new random window instead of replaying the cached page.
    func loadFeed(context: ModelContext? = nil, forceFresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        cursor = nil
        exhausted = false
        rankedBuffer = []
        servedIds = []
        cacheBuster = forceFresh ? String(Int(Date().timeIntervalSince1970 * 1000)) : nil

        // Instant paint from the SwiftData cache while network + ranking run.
        if let context, posts.isEmpty {
            loadFromCache(context: context)
        }

        await refreshTasteCentroid()
        do {
            try await fetchAndRankNextPage()
            posts = drain(uiPageSize)
            // The first card a user sees on every open/refresh should be a
            // swipeable carousel (a real multi-image product), not a static
            // single Pinterest photo — and a different one each time.
            ensureCarouselFirst()
            if let context {
                cacheResults(posts, context: context)
            }
        } catch {
            if posts.isEmpty { self.error = error.localizedDescription }
        }

        isLoading = false
    }

    // Lead with a carousel. Prefer a randomly chosen multi-image post already
    // in view (varies the hero each open/refresh); if none made this page, pull
    // the next carousel from the ranked buffer so slot 0 is still a gallery.
    private func ensureCarouselFirst() {
        guard posts.count > 1 else { return }
        if posts[0].product.gallery.count > 1 { return }

        let galleryIndices = posts.enumerated()
            .filter { $0.element.product.gallery.count > 1 }
            .map(\.offset)
        if let pick = galleryIndices.randomElement() {
            let post = posts.remove(at: pick)
            posts.insert(post, at: 0)
            return
        }
        // Nothing in view — borrow one from the not-yet-shown ranked buffer.
        if let bufIdx = rankedBuffer.firstIndex(where: { $0.post.product.gallery.count > 1 }) {
            let candidate = rankedBuffer.remove(at: bufIdx)
            servedIds.insert(candidate.post.id)
            var post = candidate.post
            if post.reason == nil { post.reason = candidate.reason }
            posts.insert(post, at: 0)
        }
    }

    /// Taste changed. Don't leave the previous profile's ranked cards on screen
    /// or behind a cursor/cache boundary; rebuild the very first page with the
    /// new vibe facets and current on-device taste snapshot.
    func reloadForPersonalization(context: ModelContext? = nil) async {
        guard !isLoading else { return }
        posts = []
        error = nil
        cursor = nil
        exhausted = false
        rankedBuffer = []
        servedIds = []
        impressedIds = []
        centroid = nil
        await loadFeed(context: context)
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

    // One candidate fetch + full local ranking pass. The fetch stays cheap and
    // cacheable, but carries the consult's cold-start signals (genderPref →
    // recipient facet, world vibes) so a brand-new user's very first page
    // already leans their way — the on-device ranker needs interactions the
    // user doesn't have yet.
    private func fetchAndRankNextPage() async throws {
        let consultVibes = PersonalizationStore.consultVibes
        let page = try await api.fetchFeed(
            cursor: cursor,
            limit: networkPageSize,
            vibes: consultVibes.isEmpty ? nil : consultVibes,
            recipient: PersonalizationStore.feedRecipient,
            userId: userId,
            // Only the FIRST page of a refresh busts the cache; cursor pages
            // are already unique URLs.
            cacheBuster: cursor == nil ? cacheBuster : nil
        )
        cursor = page.cursor
        if page.cursor == nil || page.posts.isEmpty { exhausted = true }

        let profile = await TasteProfileStore.shared.snapshot()
        let similarities = await vectorSimilarities(for: page.posts)
        let negSimilarities = await negVectorSimilarities(for: page.posts)

        let fresh = page.posts.filter { !servedIds.contains($0.id) }
        let ranked = OnDeviceRanker.rank(
            candidates: fresh,
            profile: profile,
            centroid: centroid,
            vectorSimilarities: similarities,
            negSimilarities: negSimilarities,
            context: RankingContext(
                recipient: PersonalizationStore.feedRecipient,
                consultVibes: PersonalizationStore.consultVibes,
                mindset: GiftMindset.current()
            )
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
        if profile.seedKeys.count >= 3 {
            await ensureVectorsCached(keys: profile.seedKeys)
            centroid = await VectorStore.shared.centroid(of: profile.seedKeys)
        }
        // Negative centroid needs less evidence: two hard no's already tell us
        // a direction to avoid.
        if profile.negSeedKeys.count >= 2 {
            await ensureVectorsCached(keys: profile.negSeedKeys)
            negCentroid = await VectorStore.shared.centroid(of: profile.negSeedKeys)
        } else {
            negCentroid = nil
        }
    }

    private func vectorSimilarities(for candidates: [Post]) async -> [String: Float] {
        guard let centroid else { return [:] }
        let keys = candidates.map(\.id)
        await ensureVectorsCached(keys: keys)
        return await VectorStore.shared.similarities(keys: keys, to: centroid)
    }

    private func negVectorSimilarities(for candidates: [Post]) async -> [String: Float] {
        guard let negCentroid else { return [:] }
        let keys = candidates.map(\.id)
        await ensureVectorsCached(keys: keys) // no-op when the positive pass cached them
        return await VectorStore.shared.similarities(keys: keys, to: negCentroid)
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

    // Viewport dwell (from ImpressionTracker). ≥3s of attention is a real
    // signal — scaled up to ~2× at 10s+; short glances are already counted by
    // the impression. Device-only, once per post per session.
    func recordDwell(for post: Post, dwellMs: Double) {
        guard dwellMs >= 3000, !dwelledIds.contains(post.id) else { return }
        dwelledIds.insert(post.id)
        let scale = min(2, dwellMs / 5000)
        Task {
            var event = tasteEvent(.dwell, post)
            event.weightScale = scale
            await TasteProfileStore.shared.record(event)
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
            category: signals.category,
            giftType: post.giftType ?? "product"
        )
    }
}
