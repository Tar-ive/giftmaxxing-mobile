import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [Post] = []
    @Published var isSearching = false
    @Published var recentSearches: [String] = ["birthday gift", "candles", "tech gadgets", "home decor"]

    private let api = APIClient.shared

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true

        do {
            let page = try await api.fetchFeed(
                limit: 20,
                vibes: [trimmed]
            )
            results = page.posts
            if !recentSearches.contains(trimmed) {
                recentSearches.insert(trimmed, at: 0)
                if recentSearches.count > 10 { recentSearches.removeLast() }
            }
        } catch {
            // show empty results on failure
        }

        isSearching = false
    }
}

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()

    private let categories = [
        ("🎂", "Birthday"),
        ("💍", "Anniversary"),
        ("🏠", "Housewarming"),
        ("🎓", "Graduation"),
        ("👶", "Baby"),
        ("🎄", "Holiday"),
        ("💐", "Just Because"),
        ("✈️", "Travel"),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(
                    text: $viewModel.query,
                    placeholder: "Search gifts, occasions, people...",
                    onSubmit: { Task { await viewModel.search() } }
                )
                .padding(.horizontal, 14)
                .padding(.top, 8)

                if viewModel.isSearching {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if !viewModel.results.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(viewModel.results) { post in
                                PostCardView(post: post)
                                Divider().padding(.horizontal, 14)
                            }
                        }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Categories grid
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Browse by occasion")
                                    .font(.displaySmall)
                                    .foregroundStyle(Color.ink)
                                    .padding(.horizontal, 14)

                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                ], spacing: 10) {
                                    ForEach(categories, id: \.1) { emoji, name in
                                        Button(action: {
                                            viewModel.query = name.lowercased()
                                            Task { await viewModel.search() }
                                        }) {
                                            HStack(spacing: 8) {
                                                Text(emoji)
                                                    .font(.system(size: 20))
                                                Text(name)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundStyle(Color.ink)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 12)
                                            .background(Color.cream)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 14)
                            }

                            // Recent searches
                            if !viewModel.recentSearches.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Recent searches")
                                        .font(.displaySmall)
                                        .foregroundStyle(Color.ink)
                                        .padding(.horizontal, 14)

                                    ForEach(viewModel.recentSearches, id: \.self) { term in
                                        Button(action: {
                                            viewModel.query = term
                                            Task { await viewModel.search() }
                                        }) {
                                            HStack(spacing: 10) {
                                                Image(systemName: "clock.arrow.circlepath")
                                                    .font(.system(size: 14))
                                                    .foregroundStyle(.secondary)
                                                Text(term)
                                                    .font(.bodyMedium)
                                                    .foregroundStyle(Color.ink)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        .padding(.top, 20)
                    }
                }
            }
            .background(Color.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Search")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
            }
        }
    }
}
