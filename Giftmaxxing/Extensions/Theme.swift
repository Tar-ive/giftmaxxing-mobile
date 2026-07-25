import SwiftUI

// Token surface for DESIGN.md — resolve colors, radii, spacing, and elevation
// here instead of hardcoding values in views.
extension Color {
    // Every token resolves per trait collection, so the whole app themes from
    // this one place. Dark is a WARM dark (brown-black, not blue-black) —
    // the boutique feel has to survive the switch.
    static let coral = dynamic(light: "#FB6F52", dark: "#FF7F63")
    static let coralEmphasis = dynamic(light: "#E85A3D", dark: "#FF9A80")
    static let cream = dynamic(light: "#F7F2EB", dark: "#141210")
    static let ink = dynamic(light: "#1A1A1A", dark: "#F5F1EA")
    static let inkSecondary = dynamic(light: "#6B6560", dark: "#B3ABA1")
    static let inkTertiary = dynamic(light: "#9B948C", dark: "#867E75")
    static let line = dynamic(light: "#E5E0D8", dark: "#332E28")
    static let surface = dynamic(light: "#FFFFFF", dark: "#1E1B18")
    static let surfaceSunken = dynamic(light: "#F1EAE0", dark: "#2A2620")
    static let coralSoft = dynamic(light: "#FFF0ED", dark: "#3A2620")
    static let gradientEnd = dynamic(light: "#FF9A76", dark: "#FF9A76")
    static let onboardingGlow = dynamic(light: "#FFC5A0", dark: "#7A4A33")
    static let onboardingWash = dynamic(light: "#FFF9F5", dark: "#1A1613")
    static let success = dynamic(light: "#3E8E5A", dark: "#5FB77F")
    static let danger = dynamic(light: "#D64545", dark: "#F06B6B")

    /// A color that resolves differently in light and dark appearance.
    static func dynamic(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }

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

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.coral)
            .padding(.horizontal, ThemeSpacing.lg)
            .padding(.vertical, ThemeSpacing.sm)
            .background(configuration.isPressed ? Color.surfaceSunken : Color.coralSoft)
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
