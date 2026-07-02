import SwiftUI

@MainActor
final class FeedViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?

    private var cursor: String?
    private var hasMore = true
    private let api = APIClient.shared

    func loadFeed() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        do {
            let page = try await api.fetchFeed(limit: 20)
            posts = page.posts
            cursor = page.cursor
            hasMore = page.cursor != nil
        } catch {
            self.error = error.localizedDescription
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

    func toggleLike(for post: Post) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[index].liked.toggle()
        posts[index].likes += posts[index].liked ? 1 : -1
    }

    func toggleSave(for post: Post) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[index].saved.toggle()
    }
}
