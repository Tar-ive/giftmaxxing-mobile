import SwiftUI
import GiftmaxxingCore

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var offlineQueue: OfflineQueue
    @Environment(\.scenePhase) private var scenePhase
    // Colour tokens read the active palette inside their UIColor providers, so
    // a theme switch is invisible to SwiftUI's dependency tracking — nothing it
    // watches has changed. Keying the tree on the theme is what forces the
    // repaint. Only a deliberate theme change fires it.
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var showOnboarding = false
    @State private var showSplash = true
    @State private var gateResolved = false
    // First-run navigation tour (TikTok-style coach marks) — queued the moment
    // a NEW user finishes onboarding; never for grandfathered accounts.
    // Re-presentable via Settings → "Replay app tour" (.replayCoachMarks).
    @State private var showCoachMarks = false
    // Board-save feedback: the toast + the one-time Swipe-tab callout.
    @StateObject private var boardToasts = BoardToastCenter.shared
    @State private var showBoardsHint = false
    // Invite gate for Circles + the rest of the social layer.
    @ObservedObject private var invites = InviteAccess.shared

    // Accounts are required: the cover dismisses only via real auth. E2E builds
    // sign in headlessly via launch arguments (see E2ESupport.swift).
    private var signInRequired: Binding<Bool> {
        Binding(
            get: {
                gateResolved
                    && !authManager.isAuthenticated
                    && !showSplash
                    && !showOnboarding
            },
            set: { _ in }
        )
    }

    var body: some View {
        ZStack {
            TabView(selection: $appState.selectedTab) {
                FeedView()
                    .tabItem {
                        Label(Tab.feed.rawValue, systemImage: Tab.feed.icon(selected: appState.selectedTab == .feed))
                    }
                    .tag(Tab.feed)

                SwipeView()
                    .tabItem {
                        Label(Tab.swipe.rawValue, systemImage: Tab.swipe.icon(selected: appState.selectedTab == .swipe))
                    }
                    .tag(Tab.swipe)

                SearchTabsView()
                    .tabItem {
                        Label(Tab.search.rawValue, systemImage: Tab.search.icon(selected: appState.selectedTab == .search))
                    }
                    .tag(Tab.search)

                // Circles — the whole social layer — is invite-only. Without a
                // redeemed code the tab doesn't exist at all (You → "Circles"
                // opens the code sheet).
                if invites.isUnlocked {
                    CirclesView()
                        .tabItem {
                            Label(Tab.circles.rawValue, systemImage: Tab.circles.icon(selected: appState.selectedTab == .circles))
                        }
                        .tag(Tab.circles)
                }

                Group {
                    #if DEBUG
                    if UserDefaults.standard.bool(forKey: "publicProfilePreview") {
                        NavigationStack {
                            PublicProfileView(person: PublicPerson(
                                userId: "google_102419904198993789987",
                                name: "Saksham Adhikari",
                                handle: "sakshamadhikari"
                            ))
                        }
                    } else {
                        MoreView()
                    }
                    #else
                    MoreView()
                    #endif
                }
                    .tabItem {
                        Label(Tab.you.rawValue, systemImage: Tab.you.icon(selected: appState.selectedTab == .you))
                    }
                    .tag(Tab.you)
            }
            .tint(Color.coral)

            // Maxi is one tap from every tab. The search bar's mic still opens
            // the same conversation, but voice can't be the only door — and the
            // staged Gift Journey nudges (GiftJourneyEngine) need somewhere to
            // land. `showsMaxiFAB` keeps it out of focused flows (swipe decks,
            // the taste interview, search, capture) that already own the screen.
            // `!showBoardsHint` matters: BoardsHintCallout is positioned at
            // (width * 0.9, height - 70), i.e. exactly where the FAB sits.
            if appState.showsMaxiFAB && !showBoardsHint {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        MaxiFloatingButton { appState.showMaxi = true }
                    }
                }
                .padding(.trailing, ThemeSpacing.md)
                // Standard FAB inset above the tab bar. It shares this corner
                // with each feed card's Pool / Gift-board buttons — which move,
                // so no inset can clear them. Fading while the feed is in motion
                // is what clears them: by the time you reach for a card control,
                // the FAB is out of the way.
                //
                // Opacity ONLY — the button is never unmounted mid-scroll. An
                // `if` here made SwiftUI insert/remove it on every scroll phase
                // and the corner visibly jittered.
                .padding(.bottom, 72)
                .opacity(appState.maxiFABDimmed ? 0.12 : 1)
                .scaleEffect(appState.maxiFABDimmed ? 0.92 : 1, anchor: .bottomTrailing)
                .allowsHitTesting(!appState.maxiFABDimmed)
                .animation(.easeOut(duration: 0.2), value: appState.maxiFABDimmed)
                .zIndex(6)
            }

            if !offlineQueue.isOnline {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                            .font(.caption)
                        Text("Offline mode")
                            .font(.caption.weight(.medium))
                        if offlineQueue.pendingCount > 0 {
                            Text("\(offlineQueue.pendingCount) pending")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.coral.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.ink.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(.top, 4)

                    Spacer()
                }
            }

            if showCoachMarks {
                CoachMarksView {
                    withAnimation(.easeOut(duration: 0.25)) { showCoachMarks = false }
                }
                .zIndex(8)
            }

            // "Saved to <board> · View" — global confirmation for every board
            // save, with the deep link that teaches where boards live.
            VStack {
                Spacer()
                if let event = boardToasts.event {
                    BoardSavedToast(event: event) {
                        BoardsHint.seen = true // View tap = location learned
                        boardToasts.hide()
                        appState.openBoard(event.boardId)
                    }
                }
            }
            .padding(.bottom, 62)
            .zIndex(7)
            .sensoryFeedback(.success, trigger: boardToasts.event?.id)
            .onChange(of: boardToasts.event) { old, new in
                // Toast came and went untapped after the FIRST save → point at
                // the Swipe tab once so the location still lands.
                if old != nil, new == nil, !BoardsHint.seen {
                    BoardsHint.seen = true
                    withAnimation(.snappy) { showBoardsHint = true }
                    Task {
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation(.snappy) { showBoardsHint = false }
                    }
                }
            }

            if showBoardsHint {
                GeometryReader { geo in
                    BoardsHintCallout {
                        withAnimation(.snappy) { showBoardsHint = false }
                        appState.openBoardsHome()
                    }
                    // Anchored over the You tab — always the last slot, whose
                    // centre depends on whether Circles is unlocked.
                    .position(x: geo.size.width * youTabCenterFraction, y: geo.size.height - 70)
                }
                .zIndex(7)
                .onChange(of: appState.selectedTab) { _, tab in
                    // They found it themselves — retire the pointer.
                    if tab == .you {
                        withAnimation(.snappy) { showBoardsHint = false }
                    }
                }
            }

            if showSplash {
                SplashView {
                    Task { await finishSplashAndResolveGate() }
                }
                .transition(.opacity)
                .zIndex(10)
            } else if !gateResolved {
                // Brief hold while we decide sign-in vs onboarding — prevents
                // the main chrome from flashing under a cover.
                Color.cream
                    .ignoresSafeArea()
                    .zIndex(9)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .replayCoachMarks)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { showCoachMarks = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .metaDeferredLinkReady)) { _ in
            drainMetaDeferredLink()
        }
        .sheet(isPresented: $appState.showBirthdayPerks) {
            BirthdayPerksSheet()
        }
        // Birthday-journey notification taps: a challenge for the birthday
        // person, auto-created and ready to send…
        .sheet(item: $appState.pendingChallengePrefill) { prefill in
            NavigationStack {
                ChallengeView(
                    showsClose: true,
                    prefillTheirName: prefill.recipientName,
                    autoCreate: true
                )
            }
        }
        // …and "they completed it" → straight to the responses.
        .sheet(isPresented: $appState.showChallengeResults) {
            NavigationStack {
                ChallengeView(showsClose: true)
            }
        }
        .sheet(isPresented: $appState.showMaxi) {
            MaxiView(seedRecipient: appState.maxiSeedRecipient)
                .onDisappear { appState.maxiSeedRecipient = nil }
        }
        .sheet(isPresented: $appState.showInviteCode) {
            InviteCodeSheet()
        }
        // A code redeemed (or an account switch that re-locked things) must
        // never leave the user parked on a tab that no longer renders.
        .onChange(of: invites.isUnlocked) { _, unlocked in
            if unlocked {
                if appState.pendingCircleId != nil { appState.selectedTab = .circles }
            } else if appState.selectedTab == .circles {
                appState.selectedTab = .feed
            }
        }
        .fullScreenCover(isPresented: $appState.showSearch) {
            SearchTabsView()
                .environmentObject(appState)
        }
        // DESIGN.md flow: splash → sign-in → glass intro → consult → main.
        // fullScreenCover avoids sheet/cover presentation races on iOS.
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isOnboardingComplete: Binding(
                get: { !showOnboarding },
                set: { complete in
                    guard complete else { return }
                    PersonalizationStore.markOnboarded(identity: authManager.userId)
                    CoachMarks.seen = true
                    showOnboarding = false
                    if let userId = authManager.userId {
                        Task { await syncOnboardingProfile(userId: userId) }
                    }
                }
            ))
            .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: signInRequired) {
            SignInView(showSignIn: Binding(
                get: { signInRequired.wrappedValue },
                set: { _ in }
            ))
            .environmentObject(authManager)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $appState.showCreatePoolFromCapture) {
            CreatePoolFromCaptureView(
                image: appState.poolCaptureImage,
                sourceURL: appState.poolCaptureURL
            )
            .environmentObject(appState)
        }
        .onChange(of: appState.selectedTab) { oldTab, newTab in
            AnalyticsEngine.shared.trackTabSwitch(
                from: oldTab.rawValue,
                to: newTab.rawValue
            )
        }
        .onChange(of: scenePhase) { oldPhase, phase in
            if phase == .active {
                // Reopening the app always lands on Home — the feed is the
                // front door, whatever tab was left open last session.
                if oldPhase == .background {
                    appState.selectedTab = .feed
                }
                drainCaptureInbox()
            }
        }
        .onAppear {
            drainMetaDeferredLink()
            drainCaptureInbox()
            PersonalizationStore.migrateLegacyFlagIfNeeded()
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "swipeScreenshotMode") {
                appState.selectedTab = .swipe
            } else if UserDefaults.standard.bool(forKey: "curatedScreenshotMode") {
                appState.selectedTab = .feed
            } else if UserDefaults.standard.bool(forKey: "coachMarksScreenshotMode") {
                appState.selectedTab = .feed
                showCoachMarks = true
            } else if UserDefaults.standard.bool(forKey: "profilePreview") || UserDefaults.standard.bool(forKey: "publicProfilePreview") {
                appState.selectedTab = .you
            }
            // Screenshot capture (Debug only): land directly on a screen so
            // marketing/App Store shots can be taken without hand-navigating.
            if let tab = UserDefaults.standard.string(forKey: "screenshotTab") {
                switch tab {
                case "feed": appState.selectedTab = .feed
                case "swipe": appState.selectedTab = .swipe
                case "circles" where invites.isUnlocked: appState.selectedTab = .circles
                case "you": appState.selectedTab = .you
                default: break
                }
            }
            #endif
            // Restore this account's Gift Boards + cart on launch (a restored
            // session doesn't fire onChange for the initial userId).
            SwipeListStore.shared.configure(userId: authManager.userId)
            CartStore.shared.configure(userId: authManager.userId)
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "curatedScreenshotMode"), CartStore.shared.isEmpty,
               let journey = CuratedGiftStore.shared.catalog.journeys.first {
                CartStore.shared.addAll(
                    CuratedGiftStore.shared.products(for: journey).map(\.post) + CuratedGiftStore.shared.wrapPosts,
                    for: nil,
                    source: "curated-screenshot"
                )
            }
            #endif
            DebugSessionManager.shared.handleIdentityChange(email: authManager.email)
        }
        .onChange(of: authManager.userId) { _, newUserId in
            let claimedGuest = newUserId.map { PersonalizationStore.claimGuestOnboarding(identity: $0) } ?? false
            // Privacy boundary: a different account (or a sign-out) on this
            // device must never see the previous account's pools, boards,
            // points, or persona texts.
            AccountLocalState.handleIdentityChange(newUserId)
            // Bind Gift Boards + cart to the new identity and pull that
            // account's copies from the server (survives sign-out + new devices).
            SwipeListStore.shared.configure(userId: newUserId)
            CartStore.shared.configure(userId: newUserId)
            // Design variants are an operator tool — re-evaluate on every
            // identity change so signing in as anyone else drops back to the
            // shipped design immediately.
            DebugSessionManager.shared.handleIdentityChange(email: authManager.email)
            // A fresh sign-in lands on Home, not wherever sign-in happened.
            if newUserId != nil {
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "swipeScreenshotMode") {
                    appState.selectedTab = .swipe
                } else {
                    appState.selectedTab = (UserDefaults.standard.bool(forKey: "profilePreview") || UserDefaults.standard.bool(forKey: "publicProfilePreview")) ? .you : .feed
                }
                #else
                appState.selectedTab = .feed
                #endif
            }
            if let newUserId, claimedGuest {
                Task { await syncOnboardingProfile(userId: newUserId) }
                if !CoachMarks.seen { showCoachMarks = true }
            }
            guard !showSplash else { return }
            Task { await resolveAppGate(userId: newUserId) }
        }
        .onOpenURL(perform: handleIncomingURL)
        .sheet(item: Binding(
            get: { appState.pendingChallengeId.map(ChallengeRef.init) },
            set: { appState.pendingChallengeId = $0?.id }
        )) { ref in
            ChallengeSwipeView(challengeId: ref.id)
                .environmentObject(authManager)
        }
        // See `themeManager` above — forces the repaint a theme switch cannot
        // otherwise trigger.
        .id(themeManager.theme)
    }

    private func drainMetaDeferredLink() {
        guard let url = MetaDeferredLink.takePendingURL() else { return }
        handleIncomingURL(url)
    }

    private func handleIncomingURL(_ url: URL) {
        if let circleId = CircleStore.circleId(fromURL: url) {
            appState.openCircle(circleId)
            return
        }
        // Challenge invites open the NATIVE deck — app users never bounce
        // to the web guest page.
        if let challengeId = InviteLink.challengeId(fromURL: url) {
            appState.pendingChallengeId = challengeId
            return
        }
        guard url.scheme == "giftmaxxing" else { return }
        drainCaptureInbox()
    }

    // Centre of the last tab slot, as a fraction of screen width.
    private var youTabCenterFraction: CGFloat {
        let tabs = Tab.visible(inviteUnlocked: invites.isUnlocked)
        return (CGFloat(tabs.count) - 0.5) / CGFloat(tabs.count)
    }

    @MainActor
    private func finishSplashAndResolveGate() async {
        await E2ESupport.autoSignInIfRequested(authManager: authManager)
        await resolveAppGate(userId: authManager.userId)
        withAnimation(.easeOut(duration: 0.35)) {
            showSplash = false
        }
    }

    @MainActor
    private func resolveAppGate(userId: String?) async {
        gateResolved = false
        defer { gateResolved = true }

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "signInScreenshotMode") {
            showOnboarding = false
            return
        }
        #endif

        if PersonalizationStore.hasOnboarded(identity: userId) {
            // Grandfather accounts that onboarded before the tour shipped —
            // the coach marks are a NEW-user ritual, not a changelog.
            CoachMarks.seen = true
            showOnboarding = false
            return
        }

        // Collect taste before login. The stable guest profile is claimed by
        // the first account that signs in, so these answers are never lost.
        guard authManager.isAuthenticated, let userId else {
            showOnboarding = true
            return
        }

        if let profile = try? await APIClient.shared.fetchMe(userId: userId),
           profile.completedAt != nil {
            if let pref = profile.genderPref { PersonalizationStore.genderPref = pref }
            PersonalizationStore.markOnboarded(identity: userId)
            CoachMarks.seen = true // onboarded elsewhere (web) — skip the tour
            showOnboarding = false
        } else {
            showOnboarding = true
        }
    }

    private func syncOnboardingProfile(userId: String) async {
        var profile: [String: Any] = [
            "completedAt": Date().timeIntervalSince1970 * 1000,
            "interests": Array(Set(GiftingPrefs.giftStyles + PersonalizationStore.consultVibes)),
            "onboardingPersona": GiftingPrefs.persona ?? "",
            "onboardingRelationships": GiftingPrefs.relationships,
            "onboardingBudget": GiftingPrefs.budget ?? "",
            "recipientSegment": GiftingPrefs.recipientSegment ?? "",
            "inviteCount": GiftingPrefs.inviteCount,
        ]
        if let name = GiftingPrefs.preferredName, !name.isEmpty { profile["name"] = name }
        try? await APIClient.shared.saveMeRaw(userId: userId, profile: profile)
    }

    private func drainCaptureInbox() {
        guard let capture = CaptureInbox.consume() else { return }
        appState.handleCapture(image: capture.image, url: capture.url, intent: capture.intent)
    }
}
