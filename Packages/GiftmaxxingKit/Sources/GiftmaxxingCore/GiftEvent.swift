import Foundation

public struct GiftEvent: Identifiable, Codable, Hashable {
    public let id: String
    public var userId: String?
    public var recipientId: String?
    public var type: String
    public var title: String
    public var date: Date
    public var recipientName: String
    public var recurrence: String?
    public var reminderLeadDays: Int?
    public var budget: Double?
    public var notes: String?
    public var scope: String?
    public var createdAt: Date?

    public init(
        id: String,
        userId: String? = nil,
        recipientId: String? = nil,
        type: String,
        title: String,
        date: Date,
        recipientName: String,
        recurrence: String? = nil,
        reminderLeadDays: Int? = nil,
        budget: Double? = nil,
        notes: String? = nil,
        scope: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.recipientId = recipientId
        self.type = type
        self.title = title
        self.date = date
        self.recipientName = recipientName
        self.recurrence = recurrence
        self.reminderLeadDays = reminderLeadDays
        self.budget = budget
        self.notes = notes
        self.scope = scope
        self.createdAt = createdAt
    }


    public var daysUntil: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let targetDay = Calendar.current.startOfDay(for: date)
        return max(0, Calendar.current.dateComponents([.day], from: today, to: targetDay).day ?? 0)
    }

    public var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    /// SF Symbol for this occasion — what the UI draws (AppIcons).
    public var eventTypeSymbol: String { AppIcons.event(type) }

    /// Emoji kept ONLY for outbound text (share sheets, DM copy), never as UI.
    public var eventTypeIcon: String {
        switch type {
        case "birthday": return "🎂"
        case "anniversary": return "💍"
        case "holiday": return "🎄"
        case "graduation": return "🎓"
        case "wedding": return "💒"
        case "housewarming": return "🏠"
        case "baby_shower": return "👶"
        default: return "🎁"
        }
    }
}
