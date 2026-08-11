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
    // "Add to cart" from a card's … menu — asks who it's for.
    @State private var cartPickerPost: Post?
    @State private var selectedJourney: CuratedGiftJourney?
    @State private var showIdeas = false
    @State private var showCart = false
    @ObservedObject private var swipeList = SwipeListStore.shared
    @ObservedObject private var postingStore = UGCPostingStore.shared
    @State private var refreshed = false
    // Two-tier browse taxonomy. Theme selects the query; tag narrows it in
    // place. Both live here rather than in the view model so the bars can
    // animate independently of a network round-trip.
    @State private var themeId: String = FeedTheme.all.first?.id ?? "for-you"
    @State private var themes = FeedTheme.all
    @State private var tagId: String?
    @State private var showFilterSheet = false
    // Tier-2 hides on down-scroll and returns on up-scroll. Tier 1 never hides:
    // it is navigation, and losing it mid-scroll strands you in a category with
    // no way back.
    @State private var tagBarHidden = false
    @State private var lastScrollY: CGFloat = .greatestFiniteMagnitude
    @State private var scrollOrigin: CGFloat = .greatestFiniteMagnitude
    @State private var atTop = true
    // Which feed layout to draw. Locked to A for everyone but an allowlisted
    // operator account (DebugSessionManager).
    @ObservedObject private var debugSession = DebugSessionManager.shared
    private var variant: DesignVariant { DebugSessionManager.active }

    private var activeTheme: FeedTheme {
        themes.first { $0.id == themeId } ?? themes[0]
    }
    private var activeTag: FeedTag? {
        activeTheme.tags.first { $0.id == tagId }
    }


    // One post rendered as a full-width card. Community posts only — see the
    // segment comment in `body`.
    @ViewBuilder
    private func fullWidthCard(for post: Post, at index: Int) -> some View {
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
                AnalyticsEngine.shared.trackContentAction(.contentLike, postId: post.id)
            },
            onAddToSwipeList: {
                listPickerPost = post
                AnalyticsEngine.shared.trackContentAction(.contentSave, postId: post.id)
            },
            onProductTap: {
                selectedPost = post
                AnalyticsEngine.shared.trackContentAction(.contentTap, postId: post.id)
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
            onHide: { viewModel.hide(postId: post.id) },
            onAddToCart: { cartPickerPost = post }
        )
        .onAppear {
            viewModel.recordImpression(for: post)
            viewModel.prefetchImages(around: index)
        }
        .trackImpression(
            postId: post.id,
            position: index,
            source: "feed",
            attribution: viewModel.attribution(for: post.id, at: index)
        ) { dwellMs in
            viewModel.recordDwell(for: post, dwellMs: dwellMs)
        }
        .trackScrollAnalytics(currentPosition: index)
    }

    // Ranked order, chopped into runs of products (one grid each) and single
    // UGC posts (one full-width card each).
    private struct FeedSegment: Identifiable {
        enum Kind {
            case products([Post])
            case ugc(Post)
        }
        let id: String
        let kind: Kind
        let startIndex: Int
    }

    private var feedSegments: [FeedSegment] {
        var segments: [FeedSegment] = []
        var run: [Post] = []
        var runStart = 0

        func flush() {
            guard !run.isEmpty else { return }
            segments.append(FeedSegment(id: "grid-\(run[0].id)", kind: .products(run), startIndex: runStart))
            run = []
        }

        for (index, post) in viewModel.posts.enumerated() {
            if post.source == "ugc" {
                flush()
                segments.append(FeedSegment(id: "ugc-\(post.id)", kind: .ugc(post), startIndex: index))
            } else {
                if run.isEmpty { runStart = index }
                run.append(post)
            }
        }
        flush()
        return segments
    }

    // Identity row: + · giftmaxxing · cart.
    //
    // The wordmark is CENTRED, with the two controls hung off the edges — a
    // plain HStack would centre it between them and drift as the cart badge
    // changes width. A ZStack pins it to the true centre of the screen.
    private var identityRow: some View {
        ZStack {
            Text("giftmaxxing")
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.ink)

            HStack {
                Button { appState.showCreate = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New post")

                Spacer()

                CartButton { showCart = true }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    /// The identity row is only earned by an unfiltered feed at the top.
    ///
    /// Once you pick a category — or a sub-filter, or scroll — you are browsing,
    /// and the row that identifies the app is the least useful thing on screen.
    /// Giving its height back to the grid is worth more than the branding.
    private var showsIdentityRow: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "curatedScreenshotMode") { return true }
        #endif
        return themeId == themes.first?.id && tagId == nil && atTop
    }

    // Pinned header: identity row (conditional) THEN the category pills, THEN
    // the sub-filters. Order matters — pills sat above the wordmark before,
    // which read as the categories belonging to the status bar.
    @ViewBuilder
    private var stickyHeader: some View {
        VStack(spacing: 0) {
            if showsIdentityRow {
                identityRow
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            FeedThemeBar(themes: themes, selection: $themeId)

            if !activeTheme.tags.isEmpty && !tagBarHidden {
                FeedTagBar(
                    tags: activeTheme.tags,
                    selection: $tagId,
                    onOpenFilter: { showFilterSheet = true }
                )
                .padding(.bottom, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(.regularMaterial)
        .animation(.snappy(duration: 0.22), value: showsIdentityRow)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 1) {
                    // This pilot starts from four manually reviewed source
                    // posts. Nothing from the legacy catalog is mixed in until
                    // the curation proves useful.
                    CuratedJourneyRail(
                        onSelect: { selectedJourney = $0 },
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
                        // Feed layout is LOCKED to the masonry grid — the
                        // variant experiment settled on it. Variants still
                        // differ elsewhere (Create, Circles, accent).
                        //
                        // Products go in the grid; UGC does NOT. A grid tile
                        // cannot carry a video, a music track or a carousel, so
                        // community posts keep the full-width card and the feed
                        // renders as alternating runs: grid, grid, grid, UGC
                        // card, grid… Ranked order is preserved exactly.
                        ForEach(feedSegments) { segment in
                            switch segment.kind {
                            case .products(let posts):
                                MasonryFeedGrid(
                                    posts: posts,
                                    savedIds: Set(posts.filter { swipeList.containsInMyGiftIdeas($0) }.map(\.id)),
                                    onTap: { post in
                                        selectedPost = post
                                        AnalyticsEngine.shared.trackContentAction(.contentTap, postId: post.id)
                                    },
                                    onSave: { post in
                                        swipeList.toggleMyGiftIdea(post)
                                        viewModel.toggleSave(for: post, context: modelContext)
                                        AnalyticsEngine.shared.trackContentAction(.contentSave, postId: post.id)
                                    }
                                )
                                .onAppear {
                                    for post in posts { viewModel.recordImpression(for: post) }
                                }
                                .padding(.bottom, 10)

                            case .ugc(let post):
                                fullWidthCard(for: post, at: segment.startIndex)
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
                // Sticky browse header. safeAreaInset rather than an overlay so
                // the grid's own content inset accounts for it — an overlay
                // would hide the first row behind the bars.
                // Collapsing two-tier header.
                //
                //   At rest      → Tier 1 (search + cart) and Tier 2 (category
                //                  capsules) are both visible.
                //   Scrolled     → Tier 1 collapses away entirely and Tier 2
                //                  locks to the top edge.
                //   Back at top  → Tier 1 returns.
                //
                // Search is deliberately unreachable mid-scroll: the row is
                // worth its height only when you have stopped browsing, and
                // reclaiming it gives the grid a full extra row of product.
                .safeAreaInset(edge: .top, spacing: 0) { stickyHeader }
                .onChange(of: themeId) { _, _ in
                    // A new macro theme drops the old micro tag — "Pour-over
                    // kits" is meaningless under Beauty.
                    tagId = nil
                    withAnimation(.snappy) { tagBarHidden = false }
                    Task { await viewModel.setBrowse(theme: activeTheme, tag: nil, context: modelContext) }
                }
                .onChange(of: tagId) { _, _ in
                    Task { await viewModel.setBrowse(theme: activeTheme, tag: activeTag, context: modelContext) }
                }
                .sheet(isPresented: $showFilterSheet) {
                    FeedFilterSheet(theme: activeTheme, selection: $tagId)
                }
                // Fade the Maxi FAB out while the feed moves. It shares the
                // bottom-right corner with each card's Pool / Gift-board
                // buttons, and those scroll — so "get out of the way while
                // scrolling" is the only rule that actually clears them.
                .onScrollActivityChange { moving in
                    guard moving != appState.isScrolling else { return }
                    withAnimation(.easeOut(duration: 0.18)) { appState.isScrolling = moving }
                }
                // Direction, not just motion: down hides the tag bar, up brings
                // it straight back. The 12pt threshold keeps a jittery finger
                // from flapping it open and shut.
                .onScrollOffsetChange { y in
                    if scrollOrigin == .greatestFiniteMagnitude { scrollOrigin = y }
                    let scrolled = scrollOrigin - y

                    // The identity row comes back only at the very top.
                    let top = scrolled <= 8
                    if top != atTop { atTop = top }
                    // The capsules hide once you are properly into the grid and
                    // come back the moment you scroll up.
                    defer { lastScrollY = y }
                    guard lastScrollY != .greatestFiniteMagnitude else { return }
                    let delta = y - lastScrollY
                    guard abs(delta) > 12 else { return }
                    let hide = delta < 0 && scrolled > 120
                    guard hide != tagBarHidden else { return }
                    withAnimation(.snappy(duration: 0.22)) { tagBarHidden = hide }
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
                // Programmatic pushes for the header controls. These must live
                // INSIDE the NavigationStack to resolve.
                .navigationDestination(isPresented: $showCart) { CartView() }
                .navigationDestination(isPresented: $showIdeas) { CuratedJourneyListView() }
                .navigationDestination(item: $selectedJourney) { journey in
                    CuratedJourneyDetailView(journey: journey)
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
        .sheet(item: $cartPickerPost) { post in
            RecipientPickerSheet(posts: [post], source: "feed")
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
            if let remote = try? await APIClient.shared.fetchFeedTaxonomy(), !remote.isEmpty {
                themes = remote
                if !themes.contains(where: { $0.id == themeId }) { themeId = themes[0].id }
            }
            // appState.currentUser is never populated — AuthManager owns identity.
            viewModel.userId = authManager.userId
            if viewModel.posts.isEmpty {
                AnalyticsEngine.shared.trackScreenView(screen: "feed")
                await viewModel.loadFeed(context: modelContext)
            }
            // The launch brand stays uninterrupted. Notification permission is
            // requested only after the user taps the bell's enable card or the
            // explicit Settings action.
        }
        // Push taps route here (PushManager.handleNotification).
        .onReceive(NotificationCenter.default.publisher(for: .navigateToNotifications)) { _ in
            appState.openActivity()
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
