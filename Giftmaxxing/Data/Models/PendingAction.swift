import Foundation
import SwiftData

@Model
final class PendingAction {
    @Attribute(.unique) var actionId: String
    var method: String
    var path: String
    var bodyJson: String?
    var createdAt: Date
    var retryCount: Int
    var maxRetries: Int

    var canRetry: Bool { retryCount < maxRetries }

    init(method: String, path: String, body: [String: Any]? = nil) {
        self.actionId = UUID().uuidString
        self.method = method
        self.path = path
        if let body {
            self.bodyJson = try? String(
                data: JSONSerialization.data(withJSONObject: body),
                encoding: .utf8
            )
        }
        self.createdAt = Date()
        self.retryCount = 0
        self.maxRetries = 5
    }

    var bodyDictionary: [String: Any]? {
        guard let json = bodyJson, let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
