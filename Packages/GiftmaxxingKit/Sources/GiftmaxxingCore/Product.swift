import Foundation

public struct Product: Identifiable, Codable, Hashable {
    public let id: String
    public var name: String
    public var brand: String
    public var price: Double
    public var was: Double?
    public var grad: GradientStyle
    public var emoji: String
    public var image: String?
    // Full product-page gallery (retailer listings carry 5-10 shots; we
    // historically kept one). Populated by infra/ingest/enrich-images.mjs;
    // `image` stays the cover for every single-image surface.
    public var images: [String]?

    public init(
        id: String,
        name: String,
        brand: String,
        price: Double,
        was: Double? = nil,
        grad: GradientStyle,
        emoji: String,
        image: String? = nil,
        images: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.price = price
        self.was = was
        self.grad = grad
        self.emoji = emoji
        self.image = image
        self.images = images
    }


    // Every photo we have, cover first, deduped — the detail carousel's source.
    public var gallery: [String] {
        var seen = Set<String>()
        return ([image].compactMap { $0 } + (images ?? [])).filter { seen.insert($0).inserted }
    }

    public var hasDiscount: Bool { was != nil && was! > price }
    public var discountPercent: Int? {
        guard let was, was > price else { return nil }
        return Int(((was - price) / was) * 100)
    }
}

public enum GradientStyle: String, Codable, CaseIterable, Hashable {
    case peach, rose, butter, lilac, sky, sage, coral

    public var colors: (primary: String, secondary: String) {
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
