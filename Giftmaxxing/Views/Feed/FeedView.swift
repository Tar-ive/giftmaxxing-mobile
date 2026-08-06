import SwiftUI
import SwiftData

struct FeedView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var syncEngine: SyncEngine
    @EnvironmentObject private var pushManager: PushManager
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = FeedViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPost: Post?
    @State private var selectedAuthor: PublicPerson?
    @State private var pledgingPost: Post?
    // "Add to swipe list" opens the Instagram-collections-style picker: choose
    // WHOSE list this find belongs to (or make one) instead of a blind toggle.
    @State private var listPickerPost: Post?
    @State private var selectedPack: IdeaPack?
    @State private var showIdeas = false
    @State private var showSearch = false
    @State private var showNotifications = false
    @State private var showCart = false
    // Bell badge = incoming friend requests + unseen swipe activity.
    @State private var notificationCount = 0
    @ObservedObject private var swipeList = SwipeListStore.shared
    @ObservedObject private var postingStore = UGCPostingStore.shared
    @State private var refreshed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 1) {
                    // Compact custom header (system toolbar stays hidden on
                    // Home) — the search bar IS the identity row (Amazon-style),
                    // with the notification bell and messages beside it. Shop
                    // lives in the tab bar, not up here.
                    HStack(spacing: 10) {
                        HomeSearchBar(
                            onSearchTap: { showSearch = true },
                            onCameraTap: { showSearch = true },
                            onMicTap: { appState.showMaxi = true }
                        )

                        Button {
                            showNotifications = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Color.ink)
                                if notificationCount > 0 {
                                    Text("\(min(notificationCount, 9))")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 15, height: 15)
                                        .background(Color.coral)
                                        .clipShape(Circle())
                                        .offset(x: 7, y: -6)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Notifications")

                        // Messages moved to Circles (where your people live);
                        // this slot now holds the cart, which is the thing you
                        // actually return to Home to check.
                        CartButton { showCart = true }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 8)

                    // ONE discovery rail. Curated galleries and Reddit-mined
                    // "goes together" bundles are the same thing to a user — a
                    // pack of ideas — so they share a rail, a grid and a detail
                    // screen. Group gifts moved to Circles, beside the people
                    // they're for.
                    IdeasRail(
                        onSelect: { selectedPack = $0 },
                        onSeeAll: { showIdeas = true }
                    )

                    ForEach(postingStore.items) { item in
                        PendingUGCFeedCard(item: item)
                        Divider().padding(.horizontal, 14)
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
                                inMyGiftIdeas: swipeList.containsInMyGiftIdeas(post),
                                onLike: { viewModel.toggleLike(for: post, context: modelContext) },
                                onComment: { selectedPost = post },
                                onBookmark: {
                                    swipeList.toggleMyGiftIdea(post)
                                    viewModel.toggleSave(for: post, context: modelContext)
                                },
                                onPledge: {
                                    pledgingPost = post
                                    // Pledge = the strongest positive signal the feed has.
                                    AnalyticsEngine.shared.trackContentAction(
                                        .contentLike,
                                        postId: post.id
                                    )
                                },
                                onAddToSwipeList: {
                                    listPickerPost = post
                                    AnalyticsEngine.shared.trackContentAction(
                                        .contentSave,
                                        postId: post.id
                                    )
                                },
                                onProductTap: {
                                    selectedPost = post
                                    AnalyticsEngine.shared.trackContentAction(
                                        .contentTap,
                                        postId: post.id
                                    )
                                },
                                onAuthorTap: {
                                    guard let ownerId = post.ownerId else { return }
                                    selectedAuthor = PublicPerson(
                                        userId: ownerId,
                                        name: post.user,
                                        handle: "",
                                        imageUrl: post.authorImageUrl
                                    )
                                },
                                onHide: { viewModel.hide(postId: post.id) }
                            )
                            .onAppear {
                                viewModel.recordImpression(for: post)
                                viewModel.prefetchImages(around: index)
                            }
                            // Instagram-style: track when each post enters/leaves viewport;
                            // dwell ≥ 3s upgrades the impression to a warm taste signal.
                            .trackImpression(postId: post.id, position: index, source: "feed") { dwellMs in
                                viewModel.recordDwell(for: post, dwellMs: dwellMs)
                            }
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
                .background(Color.surface)
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
                // Programmatic pushes for the header controls. These must live
                // INSIDE the NavigationStack to resolve.
                .navigationDestination(isPresented: $showSearch) { SearchTabsView() }
                .navigationDestination(isPresented: $showNotifications) {
                    NotificationsView()
                        .onDisappear {
                            // Viewing clears the unseen flags — refresh the badge.
                            Task { await refreshNotificationBadge() }
                        }
                }
                .navigationDestination(isPresented: $showCart) { CartView() }
                .navigationDestination(isPresented: $showIdeas) { IdeasView() }
                .navigationDestination(item: $selectedPack) { pack in
                    IdeaPackDetailView(pack: pack)
                }
                .navigationDestination(item: $selectedAuthor) { person in
                    PublicProfileView(person: person)
                }
            }
            .refreshable {
                // Pull-to-refresh = a genuinely fresh page (CDN bust +
                // new server random-seek), not a replay of the cache.
                await viewModel.refreshFeed(context: modelContext)
                refreshed.toggle()
            }
        }
        .sheet(item: $selectedPost) { post in
            // Read live state so like/save toggles reflect immediately.
            let live = viewModel.posts.first(where: { $0.id == post.id }) ?? post
            PostDetailView(
                post: live,
                onLike: { viewModel.toggleLike(for: live, context: modelContext) },
                onSave: {
                    swipeList.toggleMyGiftIdea(live)
                    viewModel.toggleSave(for: live, context: modelContext)
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .ugcPostReady)) { _ in
            Task { await viewModel.refreshFeed(context: modelContext) }
        }
        .sensoryFeedback(.success, trigger: refreshed)
        .sheet(item: $listPickerPost) { post in
            SwipeListPickerSheet(post: post)
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
            await refreshNotificationBadge()
            // The launch brand stays uninterrupted. Notification permission is
            // requested only after the user taps the bell's enable card or the
            // explicit Settings action.
        }
        // Push taps route here (PushManager.handleNotification).
        .onReceive(NotificationCenter.default.publisher(for: .navigateToNotifications)) { _ in
            showNotifications = true
        }
        // Messages live in Circles now — a message push switches tabs rather
        // than pushing an inbox onto the Home stack.
        .onReceive(NotificationCenter.default.publisher(for: .navigateToMessages)) { _ in
            appState.openMessages()
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

    // Bell badge = incoming pending friend requests + unseen swipe activity.
    // Two cheap reads, fired on Home load and after the inbox is viewed.
    private func refreshNotificationBadge() async {
        let userId = authManager.userId ?? InteractionQueue.anonymousUserId
        async let pending = try? APIClient.shared.listFriends(userId: userId, status: "pending")
        async let unseen = try? APIClient.shared.fetchConnections(userId: userId, unseenOnly: true)
        let incoming = (await pending ?? []).filter { $0.isPending && ($0.incoming ?? ($0.requestedBy != userId)) }
        let unseenCount = (await unseen ?? []).count
        notificationCount = incoming.count + unseenCount
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
