import Foundation

struct GiftEvent: Identifiable, Codable, Hashable {
    let id: String
    var userId: String?
    var recipientId: String?
    var type: String
    var title: String
    var date: Date
    var recipientName: String
    var recurrence: String?
    var reminderLeadDays: Int?
    var budget: Double?
    var notes: String?
    var scope: String?
    var createdAt: Date?

    var daysUntil: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let targetDay = Calendar.current.startOfDay(for: date)
        return max(0, Calendar.current.dateComponents([.day], from: today, to: targetDay).day ?? 0)
    }

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    /// SF Symbol for this occasion — what the UI draws (AppIcons).
    var eventTypeSymbol: String { AppIcons.event(type) }

    /// Emoji kept ONLY for outbound text (share sheets, DM copy), never as UI.
    var eventTypeIcon: String {
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
