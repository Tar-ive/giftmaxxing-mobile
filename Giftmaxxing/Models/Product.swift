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
    // Full product-page gallery (retailer listings carry 5-10 shots; we
    // historically kept one). Populated by infra/ingest/enrich-images.mjs;
    // `image` stays the cover for every single-image surface.
    var images: [String]?

    // Every photo we have, cover first, deduped — the detail carousel's source.
    var gallery: [String] {
        var seen = Set<String>()
        return ([image].compactMap { $0 } + (images ?? [])).filter { seen.insert($0).inserted }
    }

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
