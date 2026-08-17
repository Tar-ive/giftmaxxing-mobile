// The design system is UIKit-backed (UIColor trait resolution, UIViewRepresentable
// pickers, UIImage caching), so it only exists where UIKit does. The guard keeps
// `swift build` / `swift test` working natively on macOS for the other three
// targets — which is what makes the sub-second test loop possible.
#if canImport(UIKit)
import SwiftUI
import GiftmaxxingCore

// Token surface for DESIGN.md — resolve colors, radii, spacing, and elevation
// here instead of hardcoding values in views.
extension Color {
    // Every token resolves per trait collection, so the whole app themes from
    // this one place. Dark is a WARM dark (brown-black, not blue-black) —
    // the boutique feel has to survive the switch.
    // Light-mode coral is DEEPER than the original #FB6F52 for one reason:
    // white-on-coral measured 2.80:1 and coral-as-text on cream 2.51:1, both
    // far below the 4.5:1 AA floor. #C63F24 clears it everywhere it's used
    // (fill 5.08, on cream 4.56, on surface 5.08, on coralSoft 4.58) while
    // staying unmistakably the same coral. Dark mode already passed, so it is
    // unchanged.
    // Each token resolves through the ACTIVE palette (ThemePalette.swift) so
    // the whole app can be re-themed at runtime. `var` not `let`: a stored
    // constant would bake in whichever palette happened to be selected at
    // first access and never change again.
    public static var coral: Color { token(\.coral) }
    public static var coralEmphasis: Color { token(\.coralEmphasis) }
    public static var cream: Color { token(\.cream) }
    public static var ink: Color { token(\.ink) }
    public static var inkSecondary: Color { token(\.inkSecondary) }
    public static var inkTertiary: Color { token(\.inkTertiary) }
    public static var line: Color { token(\.line) }
    public static var surface: Color { token(\.surface) }
    public static var surfaceSunken: Color { token(\.surfaceSunken) }
    public static var coralSoft: Color { token(\.coralSoft) }
    public static var gradientEnd: Color { token(\.gradientEnd) }
    public static var onboardingGlow: Color { token(\.onboardingGlow) }
    public static var onboardingWash: Color { token(\.onboardingWash) }
    public static var success: Color { token(\.success) }
    public static var danger: Color { token(\.danger) }

    private static func token(_ path: KeyPath<Palette, (light: String, dark: String)>) -> Color {
        // Resolved inside the UIColor provider, so the palette is read at DRAW
        // time — a theme switch repaints without recreating any view's colors.
        Color(uiColor: UIColor { traits in
            var pair = ThemeManager.current[keyPath: path]
            // A design variant may override the accent (debug menu). Only the
            // accent — a variant that repainted surfaces would stop being a
            // card-layout comparison and become a second theme system.
            if path == \Palette.coral, let accent = DebugSessionManager.active.accentHex {
                pair = accent
            }
            return UIColor(Color(hex: traits.userInterfaceStyle == .dark ? pair.dark : pair.light))
        })
    }

    public static let onPrimary = Color.white

    /// A color that resolves differently in light and dark appearance.
    public static func dynamic(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }

    public init(hex: String) {
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

    public static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [.coral, .gradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static func gradient(for style: GradientStyle) -> LinearGradient {
        let colors = style.colors
        return LinearGradient(
            colors: [Color(hex: colors.primary), Color(hex: colors.secondary)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

public enum ThemeRadius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
}

public enum ThemeSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

public enum ThemeElevation {
    public static let card = (color: Color.black.opacity(0.06), radius: CGFloat(12), y: CGFloat(4))
    public static let floating = (color: Color.black.opacity(0.10), radius: CGFloat(24), y: CGFloat(8))
}

extension View {
    public func cardElevation() -> some View {
        shadow(
            color: ThemeElevation.card.color,
            radius: ThemeElevation.card.radius,
            y: ThemeElevation.card.y
        )
    }
}

public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
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

public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
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
    public static let displayLarge = Font.system(size: 28, weight: .heavy, design: .rounded)
    public static let displayMedium = Font.system(size: 22, weight: .bold, design: .rounded)
    public static let displaySmall = Font.system(size: 18, weight: .bold, design: .rounded)
    public static let bodyLarge = Font.system(size: 16, weight: .regular)
    public static let bodyMedium = Font.system(size: 14, weight: .regular)
    public static let bodySmall = Font.system(size: 12, weight: .regular)
    /// NOT named `caption`: SwiftUI already defines `Font.captionMedium`, and once the
    /// tokens moved into their own module the two became ambiguous at every call
    /// site — silently resolving to SwiftUI's dynamic caption instead of this
    /// 11pt medium. Distinct names keep the design system unambiguous.
    public static let captionMedium = Font.system(size: 11, weight: .medium)
    public static let labelBold = Font.system(size: 14, weight: .bold)
}


#endif
