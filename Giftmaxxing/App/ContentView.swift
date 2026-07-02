import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var offlineQueue: OfflineQueue
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
    @State private var showSignIn = false

    var body: some View {
        ZStack {
            TabView(selection: $appState.selectedTab) {
                FeedView()
                    .tabItem {
                        Label(Tab.feed.rawValue, systemImage: Tab.feed.icon)
                    }
                    .tag(Tab.feed)

                SearchView()
                    .tabItem {
                        Label(Tab.search.rawValue, systemImage: Tab.search.icon)
                    }
                    .tag(Tab.search)

                SwipeView()
                    .tabItem {
                        Label(Tab.swipe.rawValue, systemImage: Tab.swipe.icon)
                    }
                    .tag(Tab.swipe)

                EventsView()
                    .tabItem {
                        Label(Tab.events.rawValue, systemImage: Tab.events.icon)
                    }
                    .tag(Tab.events)

                MoreView()
                    .tabItem {
                        Label(Tab.more.rawValue, systemImage: Tab.more.icon)
                    }
                    .tag(Tab.more)
            }
            .tint(Color.coral)

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
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isOnboardingComplete: Binding(
                get: { !showOnboarding },
                set: { showOnboarding = !$0 }
            ))
            .onDisappear {
                UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                if !authManager.isAuthenticated {
                    showSignIn = true
                }
            }
        }
        .sheet(isPresented: $showSignIn) {
            SignInView(showSignIn: $showSignIn)
                .environmentObject(authManager)
        }
        .onChange(of: appState.selectedTab) { oldTab, newTab in
            AnalyticsEngine.shared.trackTabSwitch(
                from: oldTab.rawValue,
                to: newTab.rawValue
            )
        }
    }
}
