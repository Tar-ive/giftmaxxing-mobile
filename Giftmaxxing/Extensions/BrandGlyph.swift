import SwiftUI
import GiftmaxxingCore

// The brand mark: the coral gift glyph on the brand gradient, replacing the
// 🎁-as-Text logo DESIGN.md deprecates. One view so splash, Maxi, onboarding
// and empty states can't drift apart.
struct BrandGlyph: View {
    var size: CGFloat = 44
    /// Filled gradient tile (splash/Maxi) vs. a bare tinted glyph (empty states).
    var tile = true

    var body: some View {
        if tile {
            Image(systemName: AppIcons.brand)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(
                    LinearGradient(
                        colors: [Color.coral, Color.gradientEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                )
                .accessibilityHidden(true)
        } else {
            Image(systemName: AppIcons.brand)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Color.coral)
                .accessibilityHidden(true)
        }
    }
}
