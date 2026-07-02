import Foundation
import SwiftData

@Model
final class CachedInteraction {
    @Attribute(.unique) var interactionId: String
    var userId: String
    var targetId: String
    var type: String
    var createdAt: Date
    var synced: Bool

    init(userId: String, targetId: String, type: String, synced: Bool = false) {
        self.interactionId = "\(userId)#\(targetId)#\(type)"
        self.userId = userId
        self.targetId = targetId
        self.type = type
        self.createdAt = Date()
        self.synced = synced
    }
}
