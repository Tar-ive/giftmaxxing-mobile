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
    var reminderLeadDays: Int?
    var budget: Double?
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
        self.reminderLeadDays = event.reminderLeadDays
        self.budget = event.budget
        self.cachedAt = Date()
        self.synced = synced
    }

    func toGiftEvent() -> GiftEvent {
        GiftEvent(
            id: eventId,
            type: eventType,
            title: title,
            date: eventDate,
            recipientName: recipientName,
            reminderLeadDays: reminderLeadDays,
            budget: budget,
            notes: notes,
            scope: scope
        )
    }
}
