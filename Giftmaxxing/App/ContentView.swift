import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
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
    }
}
