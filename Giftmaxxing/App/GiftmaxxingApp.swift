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
                .preferredColorScheme(.light)
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
                    appState.showMaxi = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .navigateToEvent)) { _ in
                    appState.selectedTab = .you // Events live under You
                }
                .onReceive(NotificationCenter.default.publisher(for: .navigateToPool)) { _ in
                    appState.selectedTab = .circles
                }
        }
    }
}
