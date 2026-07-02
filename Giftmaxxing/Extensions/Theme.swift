import SwiftUI

extension Color {
    static let coral = Color(hex: "#FB6F52")
    static let cream = Color(hex: "#F7F2EB")
    static let ink = Color(hex: "#1A1A1A")
    static let line = Color(hex: "#E5E0D8")
    static let surface = Color(hex: "#FFFFFF")
    static let coralSoft = Color(hex: "#FFF0ED")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    static func gradient(for style: GradientStyle) -> LinearGradient {
        let colors = style.colors
        return LinearGradient(
            colors: [Color(hex: colors.primary), Color(hex: colors.secondary)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Font {
    static let displayLarge = Font.system(size: 28, weight: .heavy, design: .rounded)
    static let displayMedium = Font.system(size: 22, weight: .bold, design: .rounded)
    static let displaySmall = Font.system(size: 18, weight: .bold, design: .rounded)
    static let bodyLarge = Font.system(size: 16, weight: .regular)
    static let bodyMedium = Font.system(size: 14, weight: .regular)
    static let bodySmall = Font.system(size: 12, weight: .regular)
    static let caption = Font.system(size: 11, weight: .medium)
    static let labelBold = Font.system(size: 14, weight: .bold)
}
