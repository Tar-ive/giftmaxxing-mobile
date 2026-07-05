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
        default:
            break
        }
    }
}

extension Notification.Name {
    static let navigateToPool = Notification.Name("navigateToPool")
    static let navigateToConnection = Notification.Name("navigateToConnection")
    static let navigateToEvent = Notification.Name("navigateToEvent")
    static let navigateToMaxi = Notification.Name("navigateToMaxi")
    // The concierge consult saved fresh personalization signals — feeds refetch.
    static let consultProfileUpdated = Notification.Name("consultProfileUpdated")
}
