import UIKit
import OSLog

// Reads captures dropped by the share extension into the app-group container.
// Consumed once on app foreground: image captures route straight into visual
// search; URL captures surface a tip (Instagram/Pinterest pages can't be
// fetched server-side — a screenshot works every time).
enum CaptureInbox {
    static let appGroupID = "group.com.giftmaxxing.ios"
    private static let log = Logger(subsystem: "com.giftmaxxing.ios", category: "capture")

    enum Intent: String {
        case search   // "Find similar gifts" → visual search
        case pool     // "Start a gift pool" → pool creation prefilled with the capture
    }

    struct Capture {
        let image: UIImage?
        let url: String?
        let intent: Intent
    }

    private static var inboxURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("capture-inbox", isDirectory: true)
    }

    // Returns the pending capture (if any) and clears the inbox.
    static func consume() -> Capture? {
        guard let inbox = inboxURL else {
            log.error("app-group container unavailable \u{2014} share captures can't be read")
            return nil
        }
        let metaURL = inbox.appendingPathComponent("capture.json")
        let imageURL = inbox.appendingPathComponent("capture.jpg")

        guard let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any] else {
            return nil
        }
        log.info("capture found: type=\(meta["type"] as? String ?? "?", privacy: .public)")

        var image: UIImage?
        if let imageData = try? Data(contentsOf: imageURL) {
            image = UIImage(data: imageData)
        }
        let url = (meta["url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let intent = Intent(rawValue: meta["intent"] as? String ?? "") ?? .search

        // Clear so it's handled exactly once.
        try? FileManager.default.removeItem(at: metaURL)
        try? FileManager.default.removeItem(at: imageURL)

        guard image != nil || url != nil else { return nil }
        return Capture(image: image, url: url, intent: intent)
    }
}
