import SwiftUI
import GiftmaxxingCore

// Intentional Discover — the anti-doomscroll shelf. One finite, slower page
// (no infinite scroll, no autoplay): a couple dozen picks ranked by a
// MEANINGFULNESS score instead of recency, filterable toward gifts with a
// story and independent makers. Shop (the classic grid) lives in You → Shop.
@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var picks: [ScoredPost] = []
    @Published var isLoading = false
    @Published var filter: DiscoverFilter = .all

    static let pageSize = 24

    struct ScoredPost: Identifiable {
        let post: Post
        let score: Int
        var id: String { post.id }
    }

    enum DiscoverFilter: String, CaseIterable {
        case all = "All"
        case story = "With a story"
        case smallBusiness = "Small business"
    }

    var filtered: [ScoredPost] {
        switch filter {
        case .all:
            return picks
        case .story:
            return picks.filter { GiftStory.story(for: $0.post) != nil }
        case .smallBusiness:
            return picks.filter { GiftStory.isSmallBusiness($0.post) }
        }
    }

    func load() async {
        guard picks.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let page = try? await APIClient.shared.fetchFeed(limit: 80) else { return }
        picks = page.posts
            .filter { $0.product.image != nil }
            .map { ScoredPost(post: $0, score: Self.meaningfulness(of: $0)) }
            .sorted { $0.score > $1.score }
            .prefix(Self.pageSize)
            .map { $0 }
    }

    // Meaningfulness ≠ popularity: quality of the find, whether it has a story
    // worth telling, independent-maker provenance, and only then social proof.
    static func meaningfulness(of post: Post) -> Int {
        var score = (post.qualityScore ?? 0.5) * 50
        if GiftStory.story(for: post) != nil { score += 20 }
        if GiftStory.isSmallBusiness(post) { score += 15 }
        if post.isService { score += 5 }
        score += min(10, Double(post.likes) / 10)
        return Int(score.rounded())
    }
}

struct DiscoverView: View {
    @StateObject private var viewModel = DiscoverViewModel()
    @State private var selectedPost: Post?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(DiscoverViewModel.pageSize) picks, ranked by meaning.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)

                    // Filters
                    HStack(spacing: 8) {
                        ForEach(DiscoverViewModel.DiscoverFilter.allCases, id: \.self) { filter in
                            Button {
                                viewModel.filter = filter
                            } label: {
                                Text(filter.rawValue)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(viewModel.filter == filter ? .white : Color.ink)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(viewModel.filter == filter ? Color.ink : Color.cream)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    if viewModel.isLoading {
                        ProgressView("Choosing slowly…")
                            .font(.bodyMedium)
                            .frame(maxWidth: .infinity)
                            .padding(40)
                    } else if viewModel.filtered.isEmpty {
                        Text("Nothing under this filter yet.")
                            .font(.bodyMedium)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(40)
                    }

                    ForEach(viewModel.filtered) { pick in
                        Button {
                            selectedPost = pick.post
                        } label: {
                            discoverCard(pick)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }

                    if !viewModel.filtered.isEmpty {
                        // The finite ending is the feature.
                        VStack(spacing: 6) {
                            Image(systemName: "leaf.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.coral)
                            Text("That's all for now.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Color.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Discover")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
            }
            .sheet(item: $selectedPost) { post in
                PostDetailView(post: post)
            }
            .task {
                AnalyticsEngine.shared.trackScreenView(screen: "discover")
                await viewModel.load()
            }
            .refreshable {
                viewModel.picks = []
                await viewModel.load()
            }
        }
    }

    private func discoverCard(_ pick: DiscoverViewModel.ScoredPost) -> some View {
        let post = pick.post
        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Color.gradient(for: post.product.grad)
                    if let image = post.product.image {
                        CachedAsyncImage(url: image, width: 900)
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(4.0 / 5.0, contentMode: .fit)
                .clipped()

                // Meaningfulness badge — the ranking, made visible.
                HStack(spacing: 3) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 10))
                    Text("\(pick.score)")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.black.opacity(0.55))
                .clipShape(Capsule())
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(post.product.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if post.product.price > 0 {
                        Text("$\(Int(post.product.price))")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.coral)
                            .fixedSize()
                    }
                }
                if let story = GiftStory.story(for: post) {
                    Text(story)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(.bottom, 10)
    }
}
