import Foundation
import UIKit
import UserNotifications

@MainActor
final class PushManager: NSObject, ObservableObject {
    static let shared = PushManager()

    @Published var isRegistered = false
    @Published var permissionStatus: UNAuthorizationStatus = .notDetermined

    private let deviceTokenKey = "apns_device_token"
    private let api = APIClient.shared

    override private init() {
        super.init()
    }

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            await updatePermissionStatus()
        } catch {
            // permission denied or error
        }
    }

    func updatePermissionStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionStatus = settings.authorizationStatus
        isRegistered = settings.authorizationStatus == .authorized
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: deviceTokenKey)

        Task {
            await registerTokenWithServer(token: token)
        }
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        // APNs registration failed; push notifications won't work
    }

    private func registerTokenWithServer(token: String) async {
        guard let userId = AuthManager.shared.userId else { return }

        do {
            try await api.registerDevice(
                userId: userId,
                platform: "ios",
                token: token
            )
        } catch {
            // will retry on next launch
        }
    }

    func handleNotification(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String else { return }

        switch type {
        case "pool_contribution":
            if let poolId = userInfo["poolId"] as? String {
                NotificationCenter.default.post(
                    name: .navigateToPool,
                    object: nil,
                    userInfo: ["poolId": poolId]
                )
            }
        case "challenge_completed":
            if let connectionId = userInfo["connectionId"] as? String {
                NotificationCenter.default.post(
                    name: .navigateToConnection,
                    object: nil,
                    userInfo: ["connectionId": connectionId]
                )
            }
        case "event_reminder":
            if let eventId = userInfo["eventId"] as? String {
                NotificationCenter.default.post(
                    name: .navigateToEvent,
                    object: nil,
                    userInfo: ["eventId": eventId]
                )
            }
        case "maxi_recommendation":
            NotificationCenter.default.post(
                name: .navigateToMaxi,
                object: nil
            )
        case "birthday_freebies":
            NotificationCenter.default.post(
                name: .navigateToShop,
                object: nil
            )
        default:
            break
        }
    }
}

// Notification-center delegate — without this, taps on delivered notifications
// (local reminders AND remote pushes) never reached handleNotification at all.
// GiftmaxxingApp sets `UNUserNotificationCenter.current().delegate` at launch.
extension PushManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            self.handleNotification(userInfo: userInfo)
            completionHandler()
        }
    }

    // Keep banners visible while the app is foregrounded (default is silence).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

extension Notification.Name {
    static let navigateToPool = Notification.Name("navigateToPool")
    static let navigateToConnection = Notification.Name("navigateToConnection")
    static let navigateToEvent = Notification.Name("navigateToEvent")
    static let navigateToMaxi = Notification.Name("navigateToMaxi")
    // Birthday-freebies notification tap — ContentView opens the perks sheet.
    static let navigateToShop = Notification.Name("navigateToShop")
    // The concierge consult saved fresh personalization signals — feeds refetch.
    static let consultProfileUpdated = Notification.Name("consultProfileUpdated")
}
