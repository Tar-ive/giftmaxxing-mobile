import SwiftUI
import SwiftData
import UserNotifications

// Rebuild nudge: 2026-07-16 — verify Xcode Cloud auto-trigger on main.
// SwiftUI apps never receive the APNs registration callbacks without a real
// UIApplicationDelegate — PushManager had the handlers, but nothing delivered
// the device token to them, so no device was ever registered server-side.
// This adaptor is the missing link in the push pipeline.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushManager.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushManager.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }
}

@main
struct GiftmaxxingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var appearance = AppearanceStore.shared
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var syncEngine = SyncEngine.shared
    @StateObject private var offlineQueue = OfflineQueue.shared
    @StateObject private var pushManager = PushManager.shared

    let dataController = DataController.shared

    init() {
        // Route taps on delivered notifications (local reminders + pushes)
        // through PushManager.handleNotification — see its delegate extension.
        UNUserNotificationCenter.current().delegate = PushManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Was hard-locked to .light; the palette is trait-aware now.
                .preferredColorScheme(appearance.mode.colorScheme)
                .environmentObject(appearance)
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
                    // Re-attach any cached APNs token to the current identity
                    // (covers app updates + sign-ins that happened after the
                    // token was first issued).
                    await pushManager.registerCachedTokenIfNeeded()
                    await syncEngine.performFullSync(
                        context: dataController.mainContext,
                        userId: authManager.userId
                    )
                }
                // Account switched — the stored token must follow the new
                // identity or their pushes land on the old account.
                .onChange(of: authManager.userId) { _, _ in
                    Task { await pushManager.registerCachedTokenIfNeeded() }
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
                .onReceive(NotificationCenter.default.publisher(for: .navigateToShop)) { _ in
                    appState.showBirthdayPerks = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .navigateToBirthdayChallenge)) { note in
                    let name = note.userInfo?["recipientName"] as? String ?? ""
                    appState.pendingChallengePrefill = .init(recipientName: name)
                }
                .onReceive(NotificationCenter.default.publisher(for: .navigateToConnection)) { _ in
                    appState.showChallengeResults = true
                }
        }
    }
}
