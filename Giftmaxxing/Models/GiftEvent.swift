import Foundation

struct GiftEvent: Identifiable, Codable {
    let id: String
    var userId: String
    var recipientId: String?
    var type: String
    var title: String?
    var date: String?
    var recurrence: String?
    var reminderLeadDays: Int?
    var budget: Double?
    var createdAt: Date?

    var daysUntil: Int? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let target = formatter.date(from: date) else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        let targetDay = Calendar.current.startOfDay(for: target)
        return Calendar.current.dateComponents([.day], from: today, to: targetDay).day
    }

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
