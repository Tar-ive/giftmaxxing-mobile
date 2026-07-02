import SwiftUI
import SwiftData

struct FeedView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var syncEngine: SyncEngine
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = FeedViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPost: Post?
    @State private var storySelection: StorySelection?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 1) {
                    // Amazon-style top bar: search + camera (visual search) +
                    // mic (talk to Maxi) — the agent-first entry points.
                    HomeSearchBar(
                        onSearchTap: { appState.openSearch(.products) },
                        onCameraTap: { appState.openSearch(.visual) },
                        onMicTap: { appState.showMaxi = true }
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 6)

                    // Instagram → Amazon bridge, half two: shop what you
                    // already screenshotted.
                    ScreenshotShopRail()
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)

                    StoriesTray(onTap: { index in
                        storySelection = StorySelection(id: index)
                    })
                    .padding(.bottom, 8)

                    if viewModel.isLoading && viewModel.posts.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            PostCardSkeleton()
                        }
                    } else if let error = viewModel.error, viewModel.posts.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text(error)
                                .font(.bodyMedium)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Retry") {
                                Task { await viewModel.loadFeed(context: modelContext) }
                            }
                            .font(.labelBold)
                            .foregroundStyle(Color.coral)
                        }
                        .padding(40)
                    } else {
                        ForEach(Array(viewModel.posts.enumerated()), id: \.element.id) { index, post in
                            PostCardView(
                                post: post,
                                onLike: {
                                    viewModel.toggleLike(for: post, context: modelContext)
                                    AnalyticsEngine.shared.trackContentAction(
                                        post.liked ? .contentUnlike : .contentLike,
                                        postId: post.id
                                    )
                                },
                                onSave: {
                                    viewModel.toggleSave(for: post, context: modelContext)
                                    AnalyticsEngine.shared.trackContentAction(
                                        post.saved ? .contentUnsave : .contentSave,
                                        postId: post.id
                                    )
                                },
                                onComment: {
                                    selectedPost = post
                                },
                                onShare: {
                                    selectedPost = post
                                },
                                onProductTap: {
                                    selectedPost = post
                                    AnalyticsEngine.shared.trackContentAction(
                                        .contentTap,
                                        postId: post.id
                                    )
                                }
                            )
                            .onAppear {
                                viewModel.recordImpression(for: post)
                                viewModel.prefetchImages(around: index)
                            }
                            // Instagram-style: track when each post enters/leaves viewport
                            .trackImpression(postId: post.id, position: index, source: "feed")
                            // Scroll depth analytics
                            .trackScrollAnalytics(currentPosition: index)

                            if index < viewModel.posts.count - 1 {
                                Divider()
                                    .padding(.horizontal, 14)
                            }
                        }

                        if viewModel.isLoadingMore {
                            ProgressView()
                                .padding(20)
                        } else {
                            Color.clear
                                .frame(height: 1)
                                .onAppear {
                                    Task { await viewModel.loadMore() }
                                }
                        }
                    }
                }
            }
            .background(Color.surface)
            .refreshable {
                await viewModel.loadFeed(context: modelContext)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Single uncluttered bar: wordmark left, activity/messages right.
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        MaxiIcon(size: 24)
                        Text("giftmaxxing")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.coral)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        NavigationLink(destination: ActivityView()) {
                            Image(systemName: "heart")
                                .font(.system(size: 19))
                                .foregroundStyle(Color.ink)
                        }
                        NavigationLink(destination: MessagesView()) {
                            Image(systemName: "paperplane")
                                .font(.system(size: 19))
                                .foregroundStyle(Color.ink)
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if syncEngine.isSyncing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Syncing...")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .sheet(item: $selectedPost) { post in
            // Read live state so like/save toggles reflect immediately.
            let live = viewModel.posts.first(where: { $0.id == post.id }) ?? post
            PostDetailView(
                post: live,
                onLike: { viewModel.toggleLike(for: live, context: modelContext) },
                onSave: { viewModel.toggleSave(for: live, context: modelContext) }
            )
        }
        .fullScreenCover(item: $storySelection) { selection in
            StoryViewerView(stories: StoryItem.samples, index: selection.id)
        }
        .task {
            viewModel.userId = appState.currentUser?.id
            if viewModel.posts.isEmpty {
                AnalyticsEngine.shared.trackScreenView(screen: "feed")
                await viewModel.loadFeed(context: modelContext)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Push any locally queued interaction events before we lose runtime.
            if phase == .background { viewModel.flushInteractions() }
        }
    }
}

struct PostCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.cream)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.cream)
                        .frame(width: 100, height: 12)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.cream)
                        .frame(width: 60, height: 10)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.cream)
                .aspectRatio(1, contentMode: .fit)

            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { _ in
                    Circle()
                        .fill(Color.cream)
                        .frame(width: 24, height: 24)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color.surface)
        .redacted(reason: .placeholder)
    }
}

// Identifiable index wrapper for fullScreenCover(item:).
struct StorySelection: Identifiable {
    let id: Int
}
