import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var offlineQueue: OfflineQueue
    @Environment(\.scenePhase) private var scenePhase
    // Per-IDENTITY onboarding (see PersonalizationStore): evaluated on launch
    // for the current identity and re-evaluated whenever the account changes —
    // a brand-new sign-in runs its first consult even on a well-used device.
    @State private var showOnboarding = false
    @State private var showSplash = true

    // Accounts are required: every tester gets a distinct profile so
    // behavioral analytics attribute to real people. The cover is driven by
    // auth state — it can only dismiss by signing in. (E2E builds sign in
    // headlessly via launch arguments; see E2ESupport.swift.)
    private var signInRequired: Binding<Bool> {
        Binding(
            get: { !authManager.isAuthenticated && !showSplash && !showOnboarding },
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

                ConsultView()
                    .tabItem {
                        Label(Tab.concierge.rawValue, systemImage: Tab.concierge.icon)
                    }
                    .tag(Tab.concierge)

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

            // Floating Maxi button (Amazon Rufus-style): the agent is one tap
            // away on every tab — Maxi is the app's core interface. Hidden on
            // Concierge (that IS Maxi) and You (settings don't need it).
            if appState.selectedTab != .you && appState.selectedTab != .concierge {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        MaxiFloatingButton {
                            appState.showMaxi = true
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 62)
                    }
                }
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

            // Amazon-style animated splash on cold launch.
            if showSplash {
                SplashView {
                    withAnimation(.easeOut(duration: 0.35)) {
                        showSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .sheet(isPresented: $appState.showMaxi) {
            MaxiView()
                .presentationDragIndicator(.visible)
        }
        // Search is a modal layer (camera / products / screenshots), not a tab.
        .fullScreenCover(isPresented: $appState.showSearch) {
            SearchTabsView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isOnboardingComplete: Binding(
                get: { !showOnboarding },
                set: { showOnboarding = !$0 }
            ))
            .onDisappear {
                PersonalizationStore.markOnboarded(identity: authManager.userId)
            }
        }
        .fullScreenCover(isPresented: signInRequired) {
            SignInView(showSignIn: Binding(
                get: { signInRequired.wrappedValue },
                set: { _ in } // dismisses only via real auth state changes
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                drainCaptureInbox()
            }
        }
        .onAppear {
            drainCaptureInbox()
            PersonalizationStore.migrateLegacyFlagIfNeeded()
            Task {
                await E2ESupport.autoSignInIfRequested(authManager: authManager)
                evaluateOnboarding(for: authManager.userId)
            }
        }
        // A DIFFERENT account signed in: decide onboarding for that identity —
        // its own local flag first, then the cloud profile (completedAt set by
        // the concierge on any platform). No profile anywhere → run the consult.
        .onChange(of: authManager.userId) { _, newUserId in
            evaluateOnboarding(for: newUserId)
        }
        // giftmaxxing://capture — the share extension hands off here right
        // after "Find similar gifts" / "Start a gift pool".
        // giftmaxxing://circle/<id> (and https .../circle/<id>) — open the
        // circle page, where the inline join card greets new arrivals.
        .onOpenURL { url in
            if let circleId = CircleStore.circleId(fromURL: url) {
                appState.openCircle(circleId)
                return
            }
            guard url.scheme == "giftmaxxing" else { return }
            drainCaptureInbox()
        }
    }

    // Share-extension bridge: anything sent to Giftmaxxing from another app
    // lands in the app-group inbox and routes by the intent the user chose in
    // the extension — visual search or a new gift pool.
    private func drainCaptureInbox() {
        guard let capture = CaptureInbox.consume() else { return }
        appState.handleCapture(image: capture.image, url: capture.url, intent: capture.intent)
    }

    private func evaluateOnboarding(for userId: String?) {
        if PersonalizationStore.hasOnboarded(identity: userId) {
            showOnboarding = false
            return
        }
        guard let userId else {
            // Fresh guest — straight into the consult.
            showOnboarding = true
            return
        }
        // Signed-in identity we haven't onboarded on THIS device: the account
        // may have onboarded elsewhere (web concierge) — check /me first so
        // returning users are never re-gated, and hydrate their signals.
        Task {
            if let profile = try? await APIClient.shared.fetchMe(userId: userId),
               profile.completedAt != nil {
                if let pref = profile.genderPref { PersonalizationStore.genderPref = pref }
                PersonalizationStore.markOnboarded(identity: userId)
                showOnboarding = false
            } else {
                showOnboarding = true
            }
        }
    }
}
