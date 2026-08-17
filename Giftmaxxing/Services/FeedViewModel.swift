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
    // Interaction model phase-2 state: which slots the fast personalized
    // picks landed in, and the in-flight background refine (cancelled on
    // every reload so a stale ranking can't overwrite a fresh page).
    private var wovenPickIds: [String] = []
    private var refineTask: Task<Void, Never>?
    private var impressedIds = Set<String>()
    private var dwelledIds = Set<String>()
    private var centroid: [Float]?
    // Anti-centroid over explicitly hidden items — hides never leave the
    // device, but candidates similar to them still sink in ranking.
    private var negCentroid: [Float]?
    private var isRefreshing = false
    private var desiredLikeStates: [String: Bool] = [:]
    private var likeTasks: [String: Task<Void, Never>] = [:]

    private let networkPageSize = 40
    private let uiPageSize = 12

    // MARK: - Loading

    func hide(postId: String) {
        posts.removeAll { $0.id == postId }
        servedIds.insert(postId)
    }

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
        cacheBuster = forceFresh ? UUID().uuidString : nil

        // Instant paint from the SwiftData cache while network + ranking run.
        if let context, posts.isEmpty {
            loadFromCache(context: context)
        }

        await refreshTasteCentroid()
        do {
            // Recommendation-API-first (signed-in): the server builds a taste
            // centroid from THIS user's interaction history and kNNs the vector
            // index — richer than what a generic candidate page can carry. Runs
            // concurrently with the candidate fetch; on a cold start (no
            // interactions yet → source:"facet" or empty) it contributes
            // nothing and the generic page stands alone, so the experience is
            // seamless either way.
            async let personalizedTask = fetchPersonalizedPicks(forceFresh: forceFresh)
            try await fetchAndRankNextPage()
            posts = drain(uiPageSize)
            weave(personalized: await personalizedTask)
            // The first card a user sees on every open/refresh should be a
            // swipeable carousel (a real multi-image product), not a static
            // single Pinterest photo — and a different one each time.
            ensureCarouselFirst()
            await hydrateLikeStates()
            if let context {
                cacheResults(posts, context: context)
            }
            // Interaction model, phase 2 (intelligent back-end): the fast
            // picks above rendered instantly in cosine order; now ask the
            // MTL value model for the REAL ranking in the background and
            // upgrade the below-the-fold slots when it arrives. The user
            // never waits on the model — a cold endpoint just means this
            // pass quietly does nothing.
            refineTask?.cancel()
            refineTask = Task { [weak self] in
                await self?.refinePersonalizedPicks()
            }
        } catch {
            if posts.isEmpty { self.error = error.localizedDescription }
        }

        isLoading = false
    }

    // A pull can overlap the bottom sentinel's pagination request. Wait for that
    // request to settle instead of silently returning from loadFeed's guard.
    func refreshFeed(context: ModelContext? = nil) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        while isLoading || isLoadingMore {
            try? await Task.sleep(for: .milliseconds(50))
        }
        await loadFeed(context: context, forceFresh: true)
    }

    // Top picks from GET /recommendations?userId= (server-side interaction
    // history → vector kNN). Empty on cold start / signed out — by design.
    // rank "fast" (default) = instant cosine order; "full" = MTL value-model
    // ranking, used only by the background refine pass.
    private func fetchPersonalizedPicks(rank: String? = nil, forceFresh: Bool = false) async -> [Post] {
        guard let userId, !userId.isEmpty else { return [] }
        guard let response = try? await api.fetchVectorRecommendations(
            userId: userId,
            limit: 10,
            rank: rank,
            cacheBuster: forceFresh ? cacheBuster : nil
        ),
              response.source == "vector" || response.source == "vector+mtl",
              let items = response.items, !items.isEmpty else { return [] }
        return items.map { item in
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
                    emoji: "🎁",
                    image: item.image
                ),
                caption: "",
                likes: 0,
                productUrl: item.productUrl ?? item.url,
                reason: item.reason ?? "Picked for you",
                domain: item.domain,
                giftType: item.giftType,
                serviceDuration: item.serviceDuration
            )
        }
    }

    // Interleave personalized picks into the first page (slots 1, 4, 7, …) so
    // they lead without monopolizing — the ranked candidates still carry the
    // page. De-duped against everything already served or buffered.
    private func weave(personalized: [Post]) {
        wovenPickIds = []
        guard !personalized.isEmpty else { return }
        let known = Set(posts.map(\.id)).union(servedIds).union(rankedBuffer.map(\.post.id))
        var slot = 1
        for pick in personalized.filter({ !known.contains($0.id) && $0.product.image != nil }).prefix(4) {
            servedIds.insert(pick.id)
            posts.insert(pick, at: min(slot, posts.count))
            wovenPickIds.append(pick.id)
            slot += 3
        }
    }

    // Phase-2 refine (intelligent back-end of the interaction model): fetch
    // the MTL value-model ranking and swap it into the woven pick slots the
    // user hasn't plausibly reached — slot 1 may be on screen, so it stays;
    // slots 4/7/10 are below the fold seconds after first paint.
    private func refinePersonalizedPicks() async {
        guard wovenPickIds.count > 1 else { return }
        let refined = await fetchPersonalizedPicks(rank: "full")
        guard !refined.isEmpty, !Task.isCancelled else { return }

        let visibleSafe = Set(posts.prefix(3).map(\.id))
        var queue = refined.filter { !visibleSafe.contains($0.id) && $0.product.image != nil }
        for id in wovenPickIds.dropFirst() {
            guard let idx = posts.firstIndex(where: { $0.id == id }) else { continue }
            // next refined pick that isn't already placed elsewhere
            while let head = queue.first,
                  head.id != id, posts.contains(where: { $0.id == head.id }) {
                queue.removeFirst()
            }
            guard let pick = queue.first else { break }
            queue.removeFirst()
            if pick.id != id {
                servedIds.insert(pick.id)
                posts[idx] = pick
            }
        }
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
        guard !isRefreshing, !isLoadingMore, !isLoading, !(exhausted && rankedBuffer.isEmpty) else { return }
        isLoadingMore = true

        if rankedBuffer.count < uiPageSize, !exhausted {
            try? await fetchAndRankNextPage()
        }
        let next = drain(uiPageSize)
        posts.append(contentsOf: next)
        await hydrateLikeStates(postIds: next.map(\.id))
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

        // User-generated posts are out of the product: the app is a gift
        // search tool, not a place to post. The server may still serve legacy
        // `ugc` rows, so they're dropped here rather than rendered.
        let fresh = page.posts.filter { !servedIds.contains($0.id) && $0.source != "ugc" }
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
        let count = min(n, rankedBuffer.count)
        let batch = Array(rankedBuffer.prefix(count))
        rankedBuffer.removeFirst(count)
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
        posts[index].likes = max(0, posts[index].likes + (posts[index].liked ? 1 : -1))
        let liked = posts[index].liked
        desiredLikeStates[post.id] = liked

        if let context {
            updateCache(postId: post.id, liked: liked, likes: posts[index].likes, context: context)
        }
        guard likeTasks[post.id] == nil else { return }
        likeTasks[post.id] = Task { [weak self] in
            await self?.reconcileLike(post: post, context: context)
        }
    }

    private func reconcileLike(post: Post, context: ModelContext?) async {
        defer { likeTasks[post.id] = nil }
        while let requested = desiredLikeStates[post.id] {
            do {
                let result = try await api.setPostLike(postId: post.id, liked: requested)
                if let index = posts.firstIndex(where: { $0.id == post.id }) {
                    posts[index].liked = result.liked
                    posts[index].likes = result.likes
                    if let context {
                        updateCache(postId: post.id, liked: result.liked, likes: result.likes, context: context)
                    }
                }
                if desiredLikeStates[post.id] == requested {
                    desiredLikeStates[post.id] = nil
                }
                await TasteProfileStore.shared.record(tasteEvent(requested ? .like : .unlike, post))
                await InteractionQueue.shared.enqueue(
                    userId: userId,
                    targetId: post.id,
                    type: requested ? "like" : "unlike"
                )
                if requested { await seedVector(for: post) }
            } catch {
                desiredLikeStates[post.id] = nil
                await hydrateLikeStates(postIds: [post.id])
            }
        }
    }

    private func hydrateLikeStates(postIds: [String]? = nil) async {
        guard userId != nil else { return }
        let ids = postIds ?? posts.map(\.id)
        guard !ids.isEmpty,
              let likedIds = try? await api.fetchPostLikeStates(postIds: ids) else { return }
        let idSet = Set(ids)
        for index in posts.indices where idSet.contains(posts[index].id) {
            posts[index].liked = likedIds.contains(posts[index].id)
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
            // Same rule as the live page: no user-generated posts, including
            // ones cached before posting was removed.
            posts = cached.map { $0.toPost() }.filter { $0.source != "ugc" }
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
