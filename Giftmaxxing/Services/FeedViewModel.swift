import SwiftUI
import SwiftData

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?

    private var cursor: String?
    private var hasMore = true
    private let api = APIClient.shared

    func loadFeed(context: ModelContext? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        if let context {
            loadFromCache(context: context)
        }

        do {
            let page = try await api.fetchFeed(limit: 20)
            posts = page.posts
            cursor = page.cursor
            hasMore = page.cursor != nil

            if let context {
                cacheResults(page.posts, context: context)
            }
        } catch {
            if posts.isEmpty {
                self.error = error.localizedDescription
            }
        }

        isLoading = false
    }

    func loadMore() async {
        guard !isLoadingMore, hasMore, let cursor else { return }
        isLoadingMore = true

        do {
            let page = try await api.fetchFeed(cursor: cursor, limit: 20)
            posts.append(contentsOf: page.posts)
            self.cursor = page.cursor
            hasMore = page.cursor != nil
        } catch {
            // silently fail on load-more
        }

        isLoadingMore = false
    }

    func toggleLike(for post: Post, context: ModelContext? = nil) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[index].liked.toggle()
        posts[index].likes += posts[index].liked ? 1 : -1
        let type = posts[index].liked ? "like" : "unlike"

        if let context {
            OfflineQueue.shared.recordInteraction(
                context: context,
                userId: AuthManager.shared.userId ?? "",
                targetId: post.id,
                type: type
            )
            updateCache(postId: post.id, liked: posts[index].liked, likes: posts[index].likes, context: context)
        } else {
            Task {
                await api.recordInteraction(userId: nil, targetId: post.id, type: type)
            }
        }
    }

    func toggleSave(for post: Post, context: ModelContext? = nil) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[index].saved.toggle()
        let type = posts[index].saved ? "save" : "unsave"

        if let context {
            OfflineQueue.shared.recordInteraction(
                context: context,
                userId: AuthManager.shared.userId ?? "",
                targetId: post.id,
                type: type
            )
            updateCache(postId: post.id, saved: posts[index].saved, context: context)
        } else {
            Task {
                await api.recordInteraction(userId: nil, targetId: post.id, type: type)
            }
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
        let range = max(0, index - 2)...min(posts.count - 1, index + 5)
        let urls = posts[range].compactMap { $0.product.image }
        Task {
            await ImageLoader.shared.prefetch(urls: urls, width: 600)
        }
    }
}
