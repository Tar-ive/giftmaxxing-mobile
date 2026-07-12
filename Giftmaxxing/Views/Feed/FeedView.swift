import SwiftUI
import SwiftData

struct FeedView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var syncEngine: SyncEngine
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = FeedViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPost: Post?
    @State private var pledgingPost: Post?
    @ObservedObject private var swipeList = SwipeListStore.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Keep the horizontal tray outside the lazy feed scroll. This
                // gives its NavigationLinks a reliable hit-testing surface.
                GiftingTray()
                    .padding(.bottom, 6)

                ScrollView {
                    LazyVStack(spacing: 1) {
                    // Compact custom header (system toolbar stays hidden on
                    // Home) — ONE slim row: logo, shop, messages. Search moved
                    // into the Maxi tab (the AI search bar IS the search);
                    // the bag replaces the magnifier.
                    HStack(spacing: 6) {
                        MaxiIcon(size: 26)
                        Text("giftmaxxing")
                            .font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.coral)
                        Spacer()
                        NavigationLink(destination: ShopView()) {
                            Image(systemName: "bag")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Color.ink)
                        }
                        .accessibilityLabel("Shop")
                        NavigationLink(destination: MessagesView()) {
                            Image(systemName: "paperplane")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.ink)
                                .padding(.leading, 14)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 8)

                    if !viewModel.posts.isEmpty {
                        CompactPledgeRail(
                            posts: Array(viewModel.posts.prefix(8)),
                            onPledge: { post in
                                pledgingPost = post
                                AnalyticsEngine.shared.trackContentAction(
                                    .contentLike,
                                    postId: post.id
                                )
                            },
                            onProductTap: { post in
                                selectedPost = post
                            }
                        )
                    }

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
                                inSwipeList: swipeList.contains(post),
                                onPledge: {
                                    pledgingPost = post
                                    // Pledge = the strongest positive signal the feed has.
                                    AnalyticsEngine.shared.trackContentAction(
                                        .contentLike,
                                        postId: post.id
                                    )
                                },
                                onAddToSwipeList: {
                                    swipeList.toggle(post)
                                    AnalyticsEngine.shared.trackContentAction(
                                        swipeList.contains(post) ? .contentSave : .contentUnsave,
                                        postId: post.id
                                    )
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
                .toolbar(.hidden, for: .navigationBar)
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
        .sheet(item: $pledgingPost) { post in
            // Pledge → pool creation prefilled with this post's product.
            CreatePoolFromCaptureView(
                image: nil,
                sourceURL: post.productUrl ?? post.url,
                product: post.product
            )
            .environmentObject(appState)
        }
        .task {
            // appState.currentUser is never populated — AuthManager owns identity.
            viewModel.userId = authManager.userId
            if viewModel.posts.isEmpty {
                AnalyticsEngine.shared.trackScreenView(screen: "feed")
                await viewModel.loadFeed(context: modelContext)
            }
        }
        // Account switched: re-pull the feed under the new identity so its
        // personalization (not the previous account's) shapes the page.
        .onChange(of: authManager.userId) { _, newUserId in
            viewModel.userId = newUserId
            Task { await viewModel.loadFeed(context: modelContext) }
        }
        // The consult just wrote fresh signals (genderPref/vibes) — refetch so
        // the very next Home page reflects them.
        .onReceive(NotificationCenter.default.publisher(for: .consultProfileUpdated)) { _ in
            Task { await viewModel.reloadForPersonalization(context: modelContext) }
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

