// The design system is UIKit-backed (UIColor trait resolution, UIViewRepresentable
// pickers, UIImage caching), so it only exists where UIKit does. The guard keeps
// `swift build` / `swift test` working natively on macOS for the other three
// targets — which is what makes the sub-second test loop possible.
#if canImport(UIKit)
import SwiftUI
import GiftmaxxingCore

// Swappable colour palettes.
//
// Every colour token in Theme.swift resolves through the palette selected here,
// so a theme can be tried on the running app instead of rebuilt per variant.
// Each palette ships light AND dark values — the complaint that drove this was
// that muted mid-tones clash in dark mode, and the only way to know is to look
// at both.
//
// Contrast: text tokens are chosen to clear WCAG AA (4.5:1) against the surface
// they sit on in BOTH appearances. That is the non-negotiable part; the mood is
// the part worth experimenting with.
public struct Palette: Equatable {
    public var coral: (light: String, dark: String)
    public var coralEmphasis: (light: String, dark: String)
    public var cream: (light: String, dark: String)
    public var ink: (light: String, dark: String)
    public var inkSecondary: (light: String, dark: String)
    public var inkTertiary: (light: String, dark: String)
    public var line: (light: String, dark: String)
    public var surface: (light: String, dark: String)
    public var surfaceSunken: (light: String, dark: String)
    public var coralSoft: (light: String, dark: String)
    public var gradientEnd: (light: String, dark: String)
    public var onboardingGlow: (light: String, dark: String)
    public var onboardingWash: (light: String, dark: String)
    public var success: (light: String, dark: String)
    public var danger: (light: String, dark: String)

    public static func == (a: Palette, b: Palette) -> Bool {
        a.coral == b.coral && a.surface == b.surface && a.ink == b.ink
    }
}

public enum AppTheme: String, CaseIterable, Identifiable {
    case warmBoutique
    case midnightPlum
    case editorialMono
    case forestLuxe
    case paperCoral
    case oceanSlate
    case terracotta
    case nordicIce

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .warmBoutique: return "Warm Boutique"
        case .midnightPlum: return "Midnight Plum"
        case .editorialMono: return "Editorial Mono"
        case .forestLuxe: return "Forest Luxe"
        case .paperCoral: return "Paper & Coral"
        case .oceanSlate: return "Ocean Slate"
        case .terracotta: return "Terracotta"
        case .nordicIce: return "Nordic Ice"
        }
    }

    public var blurb: String {
        switch self {
        case .warmBoutique: return "Today's look — warm brown-black, coral accent"
        case .midnightPlum: return "Deep violet-black, punchy pink coral, ivory text"
        case .editorialMono: return "Near-black and paper white, one saturated accent"
        case .forestLuxe: return "Deep green-black with warm gold"
        case .paperCoral: return "Bright paper white, soft shadows, the original coral"
        case .oceanSlate: return "Cool blue-grey with a teal accent"
        case .terracotta: return "Clay and sand, burnt-orange accent"
        case .nordicIce: return "Very light and airy; icy blue accent"
        }
    }

    /// Three swatches for the picker: accent, surface, text.
    public var previewHexes: (accent: String, surface: String, text: String) {
        let p = palette
        return (p.coral.dark, p.surface.dark, p.ink.dark)
    }

    public var palette: Palette {
        switch self {
        // The shipped look. Coral was already tuned for AA in both modes; the
        // dark side is a WARM brown-black so the boutique feel survives.
        case .warmBoutique:
            return Palette(
                coral: ("#C63F24", "#FF7F63"),
                coralEmphasis: ("#A8321B", "#FF9A80"),
                cream: ("#F7F2EB", "#141210"),
                ink: ("#1A1A1A", "#F5F1EA"),
                inkSecondary: ("#6B6560", "#B3ABA1"),
                inkTertiary: ("#7D7670", "#867E75"),
                line: ("#E5E0D8", "#332E28"),
                surface: ("#FFFFFF", "#1E1B18"),
                surfaceSunken: ("#F1EAE0", "#2A2620"),
                coralSoft: ("#FFF0ED", "#3A2620"),
                gradientEnd: ("#FF9A76", "#FF9A76"),
                onboardingGlow: ("#FFC5A0", "#7A4A33"),
                onboardingWash: ("#FFF9F5", "#1A1613"),
                success: ("#3E8E5A", "#5FB77F"),
                danger: ("#D64545", "#F06B6B")
            )

        // Answers "flat and muted" directly: a violet-black base makes the
        // coral read as pink-hot rather than dusty, and the text is ivory at
        // near-maximum contrast (#F8F5FF on #17141F ≈ 15:1).
        case .midnightPlum:
            return Palette(
                coral: ("#C4265E", "#FF6B9D"),
                coralEmphasis: ("#9E1A4A", "#FF8FB5"),
                cream: ("#FAF7FC", "#100D17"),
                ink: ("#16121C", "#F8F5FF"),
                inkSecondary: ("#605870", "#BDB4CC"),
                inkTertiary: ("#736A82", "#8C8399"),
                line: ("#E6DFEE", "#302840"),
                surface: ("#FFFFFF", "#17141F"),
                surfaceSunken: ("#F2ECF7", "#211C2D"),
                coralSoft: ("#FFEDF3", "#3A1F2E"),
                gradientEnd: ("#FF9A76", "#B57BFF"),
                onboardingGlow: ("#FFC0D6", "#5E3A6B"),
                onboardingWash: ("#FFF8FB", "#14111C"),
                success: ("#2F8F63", "#4FCB93"),
                danger: ("#D63A57", "#FF6B84")
            )

        // Maximum legibility, zero mood colour in the chrome — every bit of
        // colour left on screen belongs to the product photography. This is the
        // one to pick if the complaint is purely contrast.
        case .editorialMono:
            return Palette(
                coral: ("#B3301A", "#FF7A55"),
                coralEmphasis: ("#8C2413", "#FF9578"),
                cream: ("#FAFAFA", "#0D0D0D"),
                ink: ("#0A0A0A", "#FFFFFF"),
                inkSecondary: ("#5C5C5C", "#C2C2C2"),
                inkTertiary: ("#707070", "#8F8F8F"),
                line: ("#E0E0E0", "#2B2B2B"),
                surface: ("#FFFFFF", "#161616"),
                surfaceSunken: ("#F2F2F2", "#1F1F1F"),
                coralSoft: ("#FFEEE9", "#331C14"),
                gradientEnd: ("#FF9A76", "#FFB08F"),
                onboardingGlow: ("#FFC5A0", "#4A2C1F"),
                onboardingWash: ("#FFFBF9", "#121212"),
                success: ("#2E7D46", "#57C77A"),
                danger: ("#C62828", "#FF6B6B")
            )

        // Gifting reads as luxury more than it reads as tech. Deep green-black
        // with a gold accent; gold on dark green is genuinely high contrast,
        // and on light it darkens to a bronze that still clears AA.
        case .forestLuxe:
            return Palette(
                coral: ("#8A6210", "#E3B341"),
                coralEmphasis: ("#6B4A08", "#F0C662"),
                cream: ("#F6F5F0", "#0F1411"),
                ink: ("#131714", "#F2F5F0"),
                inkSecondary: ("#5B655D", "#AFBAB1"),
                inkTertiary: ("#6E786F", "#828C84"),
                line: ("#DFE3DB", "#2A332C"),
                surface: ("#FFFFFF", "#161D18"),
                surfaceSunken: ("#EDF0E9", "#1F2721"),
                coralSoft: ("#FBF3DF", "#2E2717"),
                gradientEnd: ("#FF9A76", "#7FCf9F"),
                onboardingGlow: ("#EBD9A3", "#3D5245"),
                onboardingWash: ("#FCFBF6", "#121815"),
                success: ("#2F7A4E", "#63C98C"),
                danger: ("#C0392B", "#F0736A")
            )

        // The lightest of the set. Surfaces are pure white with the separation
        // carried by hairlines rather than fills, so product photography reads
        // as the only texture on screen.
        case .paperCoral:
            return Palette(
                coral: ("#C63F24", "#FF8365"),
                coralEmphasis: ("#A02F17", "#FF9E85"),
                cream: ("#FFFFFF", "#121110"),
                ink: ("#111111", "#F7F4F0"),
                inkSecondary: ("#5F5A55", "#B8B0A7"),
                inkTertiary: ("#77706A", "#8B8379"),
                line: ("#ECE7E1", "#2E2A26"),
                surface: ("#FCFAF8", "#1C1A18"),
                surfaceSunken: ("#F4F0EA", "#262320"),
                coralSoft: ("#FFF1EC", "#3A251E"),
                gradientEnd: ("#FFB08F", "#FFA98A"),
                onboardingGlow: ("#FFD3BC", "#6E4433"),
                onboardingWash: ("#FFFCFA", "#171412"),
                success: ("#2F7D4C", "#5DC183"),
                danger: ("#C93A3A", "#FF6F6F")
            )

        // A cool counterweight to everything else here, which all lean warm.
        // Worth having in the set purely to test whether the boutique warmth is
        // doing work or is just habit.
        case .oceanSlate:
            return Palette(
                coral: ("#0F7A7A", "#4FD1C5"),
                coralEmphasis: ("#0A5E5E", "#7EE3DA"),
                cream: ("#F5F7F9", "#0F1416"),
                ink: ("#121820", "#EEF3F6"),
                inkSecondary: ("#556270", "#AAB8C4"),
                inkTertiary: ("#6B7885", "#7F8C99"),
                line: ("#DDE4EA", "#28323A"),
                surface: ("#FFFFFF", "#161D22"),
                surfaceSunken: ("#EDF1F5", "#1F272D"),
                coralSoft: ("#E4F5F4", "#123033"),
                gradientEnd: ("#7FD4E8", "#6FE0D4"),
                onboardingGlow: ("#BFE6EC", "#2C4A50"),
                onboardingWash: ("#FAFCFD", "#131A1E"),
                success: ("#2C7A5A", "#4FC98F"),
                danger: ("#C0392B", "#FF7A70")
            )

        // Warmest of the set — clay, sand and burnt orange. Reads handmade
        // rather than retail, which suits the small-maker end of the catalog.
        case .terracotta:
            return Palette(
                coral: ("#B4451F", "#F08A5D"),
                coralEmphasis: ("#8F3415", "#F5A47F"),
                cream: ("#FBF5EE", "#17120F"),
                ink: ("#231A14", "#F7EEE5"),
                inkSecondary: ("#6E5B4E", "#C1B0A2"),
                inkTertiary: ("#826F61", "#93816F"),
                line: ("#E9DDD0", "#372B23"),
                surface: ("#FFFCF8", "#211913"),
                surfaceSunken: ("#F3E8DC", "#2B211A"),
                coralSoft: ("#FDEDE3", "#3E241A"),
                gradientEnd: ("#F0A868", "#F5B183"),
                onboardingGlow: ("#F6CBA6", "#6B4227"),
                onboardingWash: ("#FFFBF6", "#1C1511"),
                success: ("#3F7A4B", "#6DC183"),
                danger: ("#C0392B", "#FF7A6B")
            )

        // Almost no chroma in the chrome and a cold accent — the opposite pole
        // from Terracotta, useful as a contrast check.
        case .nordicIce:
            return Palette(
                coral: ("#2B5FA8", "#7FB4F5"),
                coralEmphasis: ("#1E477F", "#A3CBFF"),
                cream: ("#F7F9FB", "#101316"),
                ink: ("#151A1F", "#F1F5F9"),
                inkSecondary: ("#5A646E", "#AFB9C4"),
                inkTertiary: ("#6F7982", "#848E99"),
                line: ("#E2E7EC", "#262D34"),
                surface: ("#FFFFFF", "#171C21"),
                surfaceSunken: ("#EFF3F7", "#1F262C"),
                coralSoft: ("#E8F0FB", "#16232F"),
                gradientEnd: ("#A8C8F0", "#9DC6F7"),
                onboardingGlow: ("#CBDEF5", "#2A3E52"),
                onboardingWash: ("#FBFDFF", "#141A1F"),
                success: ("#2E7D57", "#5CC98D"),
                danger: ("#BF3B3B", "#FF7676")
            )
        }
    }
}

// The live selection. Tokens read `ThemeManager.shared.theme`, and the root
// view observes this object, so switching re-renders the whole app instantly —
// which is the entire point of making it swappable rather than a build flag.
@MainActor
public final class ThemeManager: ObservableObject {
    public static let shared = ThemeManager()

    private static let key = "giftmaxxing_app_theme"

    @Published public var theme: AppTheme {
        didSet {
            guard theme != oldValue else { return }
            UserDefaults.standard.set(theme.rawValue, forKey: Self.key)
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        theme = saved.flatMap(AppTheme.init(rawValue:)) ?? .warmBoutique
    }

    /// Read by the colour tokens. Non-isolated so a `static var` token can call
    /// it from anywhere without hopping actors mid-render.
    nonisolated static var current: Palette {
        let saved = UserDefaults.standard.string(forKey: key)
        return (saved.flatMap(AppTheme.init(rawValue:)) ?? .warmBoutique).palette
    }
}


#endif
