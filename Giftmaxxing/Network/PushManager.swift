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

    // Re-attach the cached token to the CURRENT identity — called on launch and
    // whenever auth changes, so pushes follow account switches and tokens
    // issued before sign-in don't strand on the anonymous id.
    func registerCachedTokenIfNeeded() async {
        guard permissionStatus == .authorized,
              let token = UserDefaults.standard.string(forKey: deviceTokenKey), !token.isEmpty
        else { return }
        await registerTokenWithServer(token: token)
    }

    private func registerTokenWithServer(token: String) async {
        // Guests get pushes too (challenge responses land on the anon sender
        // id) — the same id /connections/claim re-keys at signup.
        let userId = AuthManager.shared.userId ?? InteractionQueue.anonymousUserId

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
        case "friend_request", "friend_accept", "challenge_response", "event_reminder_bell":
            NotificationCenter.default.post(
                name: .navigateToNotifications,
                object: nil
            )
        case "dm":
            NotificationCenter.default.post(
                name: .navigateToMessages,
                object: nil,
                userInfo: ["threadId": userInfo["threadId"] as? String ?? ""]
            )
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
        case "challenge_invite":
            if let challengeId = userInfo["challengeId"] as? String {
                NotificationCenter.default.post(
                    name: .navigateToChallengeInvite,
                    object: nil,
                    userInfo: ["challengeId": challengeId]
                )
            }
        case "circle_added":
            if let circleId = userInfo["circleId"] as? String {
                NotificationCenter.default.post(
                    name: .navigateToCircle,
                    object: nil,
                    userInfo: ["circleId": circleId]
                )
            }
        case "birthday_challenge":
            // Birthday journey: tap → auto-created swipe challenge for them.
            NotificationCenter.default.post(
                name: .navigateToBirthdayChallenge,
                object: nil,
                userInfo: ["recipientName": userInfo["recipientName"] as? String ?? ""]
            )
        case "birthday_results":
            // Their challenge is done — open the results.
            NotificationCenter.default.post(
                name: .navigateToConnection,
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
    static let navigateToCircle = Notification.Name("navigateToCircle")
    static let navigateToChallengeInvite = Notification.Name("navigateToChallengeInvite")
    static let navigateToBirthdayChallenge = Notification.Name("navigateToBirthdayChallenge")
    static let navigateToEvent = Notification.Name("navigateToEvent")
    static let navigateToMaxi = Notification.Name("navigateToMaxi")
    // Birthday-freebies notification tap — ContentView opens the perks sheet.
    static let navigateToShop = Notification.Name("navigateToShop")
    // Friend-request / activity pushes land on the Home bell.
    static let navigateToNotifications = Notification.Name("navigateToNotifications")
    // DM pushes open Messages.
    static let navigateToMessages = Notification.Name("navigateToMessages")
    // The concierge consult saved fresh personalization signals — feeds refetch.
    static let consultProfileUpdated = Notification.Name("consultProfileUpdated")
}
