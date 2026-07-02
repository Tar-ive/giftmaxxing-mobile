import Foundation
import SwiftData

@Model
final class CachedEvent {
    @Attribute(.unique) var eventId: String
    var userId: String
    var title: String
    var eventDate: Date
    var recipientName: String
    var eventType: String
    var notes: String?
    var scope: String
    var cachedAt: Date
    var synced: Bool

    init(from event: GiftEvent, userId: String, synced: Bool = true) {
        self.eventId = event.id
        self.userId = userId
        self.title = event.title
        self.eventDate = event.date
        self.recipientName = event.recipientName
        self.eventType = event.type
        self.notes = event.notes
        self.scope = event.scope ?? "personal"
        self.cachedAt = Date()
        self.synced = synced
    }

    func toGiftEvent() -> GiftEvent {
        GiftEvent(
            id: eventId,
            title: title,
            date: eventDate,
            recipientName: recipientName,
            type: eventType,
            notes: notes,
            scope: scope
        )
    }
}
