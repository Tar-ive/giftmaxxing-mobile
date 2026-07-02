import Foundation

struct Product: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var brand: String
    var price: Double
    var was: Double?
    var grad: GradientStyle
    var emoji: String
    var image: String?

    var hasDiscount: Bool { was != nil && was! > price }
    var discountPercent: Int? {
        guard let was, was > price else { return nil }
        return Int(((was - price) / was) * 100)
    }
}

enum GradientStyle: String, Codable, CaseIterable, Hashable {
    case peach, rose, butter, lilac, sky, sage, coral

    var colors: (primary: String, secondary: String) {
        switch self {
        case .peach:  return ("#FFD4C2", "#FFB5A0")
        case .rose:   return ("#FFD1DC", "#FFB3C6")
        case .butter: return ("#FFF3C4", "#FFE08A")
        case .lilac:  return ("#E8D5F5", "#D4B5EF")
        case .sky:    return ("#C5E8FF", "#93D5FF")
        case .sage:   return ("#D1E7D4", "#B5D9BA")
        case .coral:  return ("#FFB5A0", "#FB6F52")
        }
    }
}
