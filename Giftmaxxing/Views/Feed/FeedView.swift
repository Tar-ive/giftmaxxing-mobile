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
    // "Add to swipe list" opens the Instagram-collections-style picker: choose
    // WHOSE list this find belongs to (or make one) instead of a blind toggle.
    @State private var listPickerPost: Post?
    // "Add to cart" from a card's … menu — asks who it's for.
    @State private var cartPickerPost: Post?
    @State private var selectedJourney: CuratedGiftJourney?
    @State private var showIdeas = false
    @State private var showCart = false
    @ObservedObject private var swipeList = SwipeListStore.shared
    @ObservedObject private var invites = InviteAccess.shared
    @State private var refreshed = false
    // Two-tier browse taxonomy. Theme selects the query; tag narrows it in
    // place. Both live here rather than in the view model so the bars can
    // animate independently of a network round-trip.
    @State private var themeId: String = FeedTheme.all.first?.id ?? "for-you"
    @State private var themes = FeedTheme.all
    @State private var tagId: String?
    @State private var showFilterSheet = false

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

                Spacer()

                CartButton { showCart = true }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var taxonomyHeader: some View {
        VStack(spacing: 0) {
            FeedThemeBar(themes: themes, selection: $themeId)

            if !activeTheme.tags.isEmpty {
                FeedTagBar(
                    tags: activeTheme.tags,
                    selection: $tagId,
                    onOpenFilter: { showFilterSheet = true }
                )
                .padding(.bottom, ThemeSpacing.xs)
            }
        }
        .background(.regularMaterial)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        identityRow
                            .id("feed-top")

                        Section {
                            if themeId == "for-you" {
                                CuratedJourneyRail(
                                    onSelect: { selectedJourney = $0 },
                                    onSeeAll: { showIdeas = true }
                                )
                            }

                            feedContent
                        } header: {
                            taxonomyHeader
                        }
                    }
                    .background(Color.surface)
                }
                .refreshable {
                    await viewModel.refreshFeed(context: modelContext)
                    refreshed.toggle()
                }
                .onChange(of: themeId) { _, _ in
                    tagId = nil
                    proxy.scrollTo("feed-top", anchor: .top)
                    Task { await viewModel.setBrowse(theme: activeTheme, tag: nil, context: modelContext) }
                }
                .onChange(of: tagId) { _, _ in
                    proxy.scrollTo("feed-top", anchor: .top)
                    Task { await viewModel.setBrowse(theme: activeTheme, tag: activeTag, context: modelContext) }
                }
                .onScrollActivityChange { moving in
                    guard moving != appState.isScrolling else { return }
                    withAnimation(.easeOut(duration: 0.18)) { appState.isScrolling = moving }
                }
            }
            .sheet(isPresented: $showFilterSheet) {
                FeedFilterSheet(theme: activeTheme, selection: $tagId)
            }
            .overlay(alignment: .top) {
                if syncEngine.isSyncing {
                    ProgressView()
                        .padding(ThemeSpacing.xs)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .navigationDestination(isPresented: $showCart) { CartView() }
            .navigationDestination(isPresented: $showIdeas) { CuratedJourneyListView() }
            .navigationDestination(item: $selectedJourney) { journey in
                CuratedJourneyDetailView(journey: journey)
            }
            .navigationDestination(item: $selectedAuthor) { person in
                PublicProfileView(person: person)
            }
            .toolbar(.hidden, for: .navigationBar)
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
        .sensoryFeedback(.success, trigger: refreshed)
        .sheet(item: $listPickerPost) { post in
            SwipeListPickerSheet(post: post)
        }
        .sheet(item: $cartPickerPost) { post in
            RecipientPickerSheet(posts: [post], source: "feed")
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

    @ViewBuilder
    private var feedContent: some View {
        if viewModel.isLoading && viewModel.posts.isEmpty {
            ForEach(0..<3, id: \.self) { _ in PostCardSkeleton() }
        } else if let error = viewModel.error, viewModel.posts.isEmpty {
            ContentUnavailableView {
                Label("Couldn’t load gifts", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { Task { await viewModel.loadFeed(context: modelContext) } }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(ThemeSpacing.xl)
        } else {
            MasonryFeedGrid(
                posts: viewModel.posts,
                savedIds: Set(viewModel.posts.filter { swipeList.containsInMyGiftIdeas($0) }.map(\.id)),
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
                for post in viewModel.posts { viewModel.recordImpression(for: post) }
            }
            .padding(.bottom, ThemeSpacing.sm)

            if viewModel.isLoadingMore {
                ProgressView().padding(ThemeSpacing.lg)
            } else {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        Task { await viewModel.loadMore(context: modelContext) }
                    }
            }
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
