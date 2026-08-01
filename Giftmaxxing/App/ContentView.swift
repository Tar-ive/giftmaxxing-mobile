import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var offlineQueue: OfflineQueue
    @Environment(\.scenePhase) private var scenePhase
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
                        Label(Tab.feed.rawValue, systemImage: Tab.feed.icon)
                    }
                    .tag(Tab.feed)

                SwipeView()
                    .tabItem {
                        Label(Tab.swipe.rawValue, systemImage: Tab.swipe.icon)
                    }
                    .tag(Tab.swipe)

                UGCCreateView()
                    .tabItem {
                        Label(Tab.create.rawValue, systemImage: Tab.create.icon)
                    }
                    .tag(Tab.create)

                CirclesView()
                    .tabItem {
                        Label(Tab.circles.rawValue, systemImage: Tab.circles.icon)
                    }
                    .tag(Tab.circles)

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
                        Label(Tab.you.rawValue, systemImage: Tab.you.icon)
                    }
                    .tag(Tab.you)
            }
            .tint(Color.coral)

            // Maxi's floating button is gone — its nudges now arrive as the
            // staged Gift Journey (GiftJourneyEngine) and the Home search bar's
            // mic opens the full conversation on demand.

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
                    // Anchored over the You tab — 5th of 5 slots (90% width),
                    // just above the ~49pt tab bar.
                    .position(x: geo.size.width * 0.9, y: geo.size.height - 70)
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
            MaxiView()
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
                    showOnboarding = false
                    // Fresh account, first landing on the main chrome — run the
                    // navigation tour once.
                    if !CoachMarks.seen { showCoachMarks = true }
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
            if UserDefaults.standard.bool(forKey: "profilePreview") || UserDefaults.standard.bool(forKey: "publicProfilePreview") {
                appState.selectedTab = .you
            }
            // Screenshot capture (Debug only): land directly on a screen so
            // marketing/App Store shots can be taken without hand-navigating.
            if let tab = UserDefaults.standard.string(forKey: "screenshotTab") {
                switch tab {
                case "feed": appState.selectedTab = .feed
                case "swipe": appState.selectedTab = .swipe
                case "post": appState.selectedTab = .create
                case "circles": appState.selectedTab = .circles
                case "you": appState.selectedTab = .you
                default: break
                }
            }
            #endif
            // Restore this account's Gift Boards on launch (a restored session
            // doesn't fire onChange for the initial userId).
            SwipeListStore.shared.configure(userId: authManager.userId)
        }
        .onChange(of: authManager.userId) { _, newUserId in
            // Privacy boundary: a different account (or a sign-out) on this
            // device must never see the previous account's pools, boards,
            // points, or persona texts.
            AccountLocalState.handleIdentityChange(newUserId)
            // Bind Gift Boards to the new identity and pull that account's
            // saved boards from the server (survives sign-out + new devices).
            SwipeListStore.shared.configure(userId: newUserId)
            // A fresh sign-in lands on Home, not wherever sign-in happened.
            if newUserId != nil {
                #if DEBUG
                appState.selectedTab = (UserDefaults.standard.bool(forKey: "profilePreview") || UserDefaults.standard.bool(forKey: "publicProfilePreview")) ? .you : .feed
                #else
                appState.selectedTab = .feed
                #endif
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
        if url.host == "create" {
            appState.selectedTab = .create
            return
        }
        drainCaptureInbox()
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

        if PersonalizationStore.hasOnboarded(identity: userId) {
            // Grandfather accounts that onboarded before the tour shipped —
            // the coach marks are a NEW-user ritual, not a changelog.
            CoachMarks.seen = true
            showOnboarding = false
            return
        }

        // Accounts are required — onboarding only runs for a signed-in identity.
        guard authManager.isAuthenticated, let userId else {
            showOnboarding = false
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

    private func drainCaptureInbox() {
        guard let capture = CaptureInbox.consume() else { return }
        appState.handleCapture(image: capture.image, url: capture.url, intent: capture.intent)
    }
}
