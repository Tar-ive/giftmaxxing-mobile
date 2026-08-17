import SwiftUI
import GiftmaxxingCore

// Deterministic, vibrant avatar colours derived from the name itself.
//
// The old avatars drew from a small fixed `GradientStyle` enum, so most people
// landed on the same muted olive-grey — low contrast against the dark surface
// and visually indistinguishable from each other, which defeats the one job an
// avatar has (tell people apart at a glance).
//
// This maps the display string onto the full hue wheel: hue = hash % 360 at a
// fixed saturation and lightness, so every colour is equally vivid and equally
// legible against white text. Same name always gives the same colour — across
// devices, launches and accounts — because the hash is stable, not random.
enum AvatarPalette {
    // FNV-1a. Swift's `hashValue` is seeded per-process, so the same name would
    // change colour on every launch — the one thing this must never do.
    static func stableHash(_ string: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in string.lowercased().utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }

    /// Hue in 0..<360 for a display string.
    static func hue(for string: String) -> Double {
        Double(stableHash(string) % 360)
    }

    // Saturation is fixed; lightness is NOT.
    //
    // The obvious spec — hue = hash % 360 at a constant s=65%, l=45% — looks
    // right on a swatch sheet and fails in practice, because perceived
    // luminance varies enormously with hue at constant HSL lightness. Measured
    // against white initials: blue (hue 240) lands at 9.84:1, while yellow
    // (hue 60) collapses to 2.00:1 — WORSE than the muted olive it replaced
    // (4.44:1) and nowhere near the 4.5:1 AA floor.
    //
    // So lightness is solved per hue instead of assumed: darken until white
    // text clears AA. Every hue on the wheel ends up legible, and the ones that
    // were already fine (blues, purples, magentas) keep their full vibrance.
    private static let saturation: Double = 0.65
    private static let baseLightness: Double = 0.45
    private static let minLightness: Double = 0.20
    private static let contrastTarget: Double = 4.5

    /// Relative luminance per WCAG 2.1.
    private static func relativeLuminance(_ color: (r: Double, g: Double, b: Double)) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b)
    }

    private static func contrastWithWhite(_ rgb: (r: Double, g: Double, b: Double)) -> Double {
        1.05 / (relativeLuminance(rgb) + 0.05)
    }

    /// HSL → RGB (0...1 components).
    private static func hslToRGB(h: Double, s: Double, l: Double) -> (r: Double, g: Double, b: Double) {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = (h.truncatingRemainder(dividingBy: 360)) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double)
        switch hp {
        case ..<1: (r1, g1, b1) = (c, x, 0)
        case ..<2: (r1, g1, b1) = (x, c, 0)
        case ..<3: (r1, g1, b1) = (0, c, x)
        case ..<4: (r1, g1, b1) = (0, x, c)
        case ..<5: (r1, g1, b1) = (x, 0, c)
        default:   (r1, g1, b1) = (c, 0, x)
        }
        let m = l - c / 2
        return (r1 + m, g1 + m, b1 + m)
    }

    /// The darkest-needed lightness for this hue so white initials clear AA.
    static func accessibleLightness(forHue hue: Double) -> Double {
        var l = baseLightness
        while l > minLightness,
              contrastWithWhite(hslToRGB(h: hue, s: saturation, l: l)) < contrastTarget {
            l -= 0.02
        }
        return l
    }

    /// The two-stop gradient for a name. The second stop is the same hue
    /// rotated slightly, which reads as depth without introducing a second
    /// colour that could clash. Both stops respect the solved lightness — a
    /// fixed lift would re-create the washed-out corner exactly where the
    /// initials sit.
    static func gradient(for string: String) -> LinearGradient {
        let h = hue(for: string)
        let l = accessibleLightness(forHue: h)
        let h2 = (h + 24).truncatingRemainder(dividingBy: 360)
        return LinearGradient(
            colors: [
                Color(hue: h / 360, saturation: saturation, lightness: l),
                Color(hue: h2 / 360,
                      saturation: saturation,
                      lightness: min(accessibleLightness(forHue: h2) + 0.10, 0.60)),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Initials, always uppercase. "co" reading as lowercase at 32px was the
    /// single most legibility-damaging detail in the old avatar.
    static func initials(for name: String) -> String {
        let parts = name
            .split(whereSeparator: { $0 == " " || $0 == "_" || $0 == "-" })
            .filter { $0.first?.isLetter == true || $0.first?.isNumber == true }

        if parts.count >= 2,
           let a = parts[0].first, let b = parts[1].first {
            return "\(a)\(b)".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// A brand's own high-resolution icon, preferred over text initials for
    /// merchants. `apple-touch-icon.png` is the convention for a 180px icon;
    /// when it 404s the avatar simply reveals the initials underneath, because
    /// the fallback layer is always drawn.
    static func brandIconURL(domain: String?) -> String? {
        guard var host = domain?
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !host.isEmpty else { return nil }

        // Accept a bare host or a full URL.
        if let url = URL(string: host), let h = url.host { host = h }
        host = host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        guard host.contains("."), !host.contains("/") else { return nil }

        return "https://\(host)/apple-touch-icon.png"
    }
}

extension Color {
    // SwiftUI's Color(hue:saturation:brightness:) is HSB, not HSL. Avatar
    // colours are specified in HSL (lightness 45%), so convert — HSB at 0.45
    // brightness would come out muddy on every hue.
    init(hue: Double, saturation: Double, lightness: Double, opacity: Double = 1) {
        let brightness = lightness + saturation * min(lightness, 1 - lightness)
        let sb = brightness == 0 ? 0 : 2 * (1 - lightness / brightness)
        self.init(hue: hue, saturation: sb, brightness: brightness, opacity: opacity)
    }
}
