import AppTrackingTransparency
import FBSDKCoreKit
import Foundation

@MainActor
enum MetaDeferredLink {
    private static var requestStarted = false
    private static var pendingURL: URL?

    static func fetchIfNeeded() {
        guard !requestStarted else { return }
        requestStarted = true

        ATTrackingManager.requestTrackingAuthorization { status in
            guard status == .authorized else { return }
            DispatchQueue.main.async {
                AppLinkUtility.fetchDeferredAppLink { url, _ in
                    guard let url else { return }
                    pendingURL = url
                    NotificationCenter.default.post(name: .metaDeferredLinkReady, object: nil)
                }
            }
        }
    }

    static func takePendingURL() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }
}

extension Notification.Name {
    static let metaDeferredLinkReady = Notification.Name("metaDeferredLinkReady")
}
