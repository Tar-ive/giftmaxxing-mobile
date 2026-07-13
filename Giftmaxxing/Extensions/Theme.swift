import SwiftUI

// Token surface for DESIGN.md — resolve colors, radii, spacing, and elevation
// here instead of hardcoding values in views.
extension Color {
    static let coral = Color(hex: "#FB6F52")
    static let coralEmphasis = Color(hex: "#E85A3D")
    static let cream = Color(hex: "#F7F2EB")
    static let ink = Color(hex: "#1A1A1A")
    static let inkSecondary = Color(hex: "#6B6560")
    static let inkTertiary = Color(hex: "#9B948C")
    static let line = Color(hex: "#E5E0D8")
    static let surface = Color(hex: "#FFFFFF")
    static let surfaceSunken = Color(hex: "#F1EAE0")
    static let coralSoft = Color(hex: "#FFF0ED")
    static let gradientEnd = Color(hex: "#FF9A76")
    static let onboardingGlow = Color(hex: "#FFC5A0")
    static let onboardingWash = Color(hex: "#FFF9F5")

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

    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [.coral, .gradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
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

enum ThemeRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum ThemeSpacing {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
}

enum ThemeElevation {
    static let card = (color: Color.black.opacity(0.06), radius: CGFloat(12), y: CGFloat(4))
    static let floating = (color: Color.black.opacity(0.10), radius: CGFloat(24), y: CGFloat(8))
}

extension View {
    func cardElevation() -> some View {
        shadow(
            color: ThemeElevation.card.color,
            radius: ThemeElevation.card.radius,
            y: ThemeElevation.card.y
        )
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.labelBold)
            .foregroundStyle(.white)
            .padding(.horizontal, ThemeSpacing.lg)
            .padding(.vertical, 14)
            .background(configuration.isPressed ? Color.coralEmphasis : Color.coral)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.35, bounce: 0.15), value: configuration.isPressed)
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
