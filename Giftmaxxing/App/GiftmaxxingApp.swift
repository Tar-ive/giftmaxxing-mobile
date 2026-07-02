import SwiftUI
import SwiftData

@main
struct GiftmaxxingApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var syncEngine = SyncEngine.shared
    @StateObject private var offlineQueue = OfflineQueue.shared
    @StateObject private var pushManager = PushManager.shared

    let dataController = DataController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(authManager)
                .environmentObject(syncEngine)
                .environmentObject(offlineQueue)
                .environmentObject(pushManager)
                .modelContainer(dataController.container)
                .task {
                    AnalyticsEngine.shared.startSession()
                    AnalyticsEngine.shared.retryPendingAnalytics()
                    await authManager.refreshTokenIfNeeded()
                    await pushManager.updatePermissionStatus()
                    await syncEngine.performFullSync(
                        context: dataController.mainContext,
                        userId: authManager.userId
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: .navigateToMaxi)) { _ in
                    appState.selectedTab = .more
                }
                .onReceive(NotificationCenter.default.publisher(for: .navigateToEvent)) { _ in
                    appState.selectedTab = .events
                }
                .onReceive(NotificationCenter.default.publisher(for: .navigateToPool)) { _ in
                    appState.selectedTab = .more
                }
        }
    }
}
