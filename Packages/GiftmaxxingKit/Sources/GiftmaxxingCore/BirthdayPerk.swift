import Foundation

public struct BirthdayPerk: Identifiable, Codable, Equatable {
    public let id: String
    public let brand: String
    public let category: String
    public let gift: String
    public let how: String
    public let window: String
    public let url: String
    public let emoji: String
    public let color: String

    public init(
        id: String,
        brand: String,
        category: String,
        gift: String,
        how: String,
        window: String,
        url: String,
        emoji: String,
        color: String
    ) {
        self.id = id
        self.brand = brand
        self.category = category
        self.gift = gift
        self.how = how
        self.window = window
        self.url = url
        self.emoji = emoji
        self.color = color
    }

}

public struct BirthdayPerksResponse: Codable {
    public let perks: [BirthdayPerk]
    public let categories: [String]
    public let updatedAt: String
}
