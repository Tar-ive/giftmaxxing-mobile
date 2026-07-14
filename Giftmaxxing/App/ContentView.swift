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
    @State private var showCoachMarks = false

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

                CirclesView()
                    .tabItem {
                        Label(Tab.circles.rawValue, systemImage: Tab.circles.icon)
                    }
                    .tag(Tab.circles)

                MoreView()
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
        .sheet(isPresented: $appState.showBirthdayPerks) {
            BirthdayPerksSheet()
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
            drainCaptureInbox()
            PersonalizationStore.migrateLegacyFlagIfNeeded()
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
                appState.selectedTab = .feed
            }
            guard !showSplash else { return }
            Task { await resolveAppGate(userId: newUserId) }
        }
        .onOpenURL { url in
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
        .sheet(item: Binding(
            get: { appState.pendingChallengeId.map(ChallengeRef.init) },
            set: { appState.pendingChallengeId = $0?.id }
        )) { ref in
            ChallengeSwipeView(challengeId: ref.id)
                .environmentObject(authManager)
        }
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
