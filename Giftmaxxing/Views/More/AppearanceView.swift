import SwiftUI
import GiftmaxxingDesignSystem

// Live theme switcher.
//
// Colour decisions do not survive being argued about in the abstract — you have
// to see the real feed in the real palette. Switching here repaints the whole
// app immediately, so the comparison is against actual product photography and
// actual text, not swatches on a page.
struct AppearanceView: View {
    @ObservedObject private var manager = ThemeManager.shared
    // The app already had a light/dark store wired at the root — reuse it
    // rather than introduce a second source of truth for the same setting.
    @ObservedObject private var appearance = AppearanceStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ThemeSpacing.md) {
                // Light/dark first: a palette is two palettes, and you cannot
                // judge one of them from Control Center without leaving the app.
                Picker("Appearance", selection: $appearance.mode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text("THEME")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.inkTertiary)
                    .padding(.top, ThemeSpacing.xs)

                ForEach(AppTheme.allCases) { theme in
                    Button {
                        withAnimation(.snappy) { manager.theme = theme }
                    } label: {
                        ThemeRow(theme: theme, selected: manager.theme == theme)
                    }
                    .buttonStyle(.plain)
                }

                Text("Switch themes and the app repaints in place. Flip Light/Dark above to check both halves of a palette without leaving.")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.top, ThemeSpacing.xs)
            }
            .padding(ThemeSpacing.md)
        }
        .background(Color.cream)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ThemeRow: View {
    let theme: AppTheme
    let selected: Bool

    var body: some View {
        let hexes = theme.previewHexes
        return HStack(spacing: ThemeSpacing.sm) {
            // A miniature of the actual thing: surface, text on it, accent.
            ZStack {
                RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous)
                    .fill(Color(hex: hexes.surface))
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: hexes.text))
                        .frame(width: 26, height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: hexes.text).opacity(0.45))
                        .frame(width: 18, height: 3)
                    Capsule()
                        .fill(Color(hex: hexes.accent))
                        .frame(width: 22, height: 7)
                        .padding(.top, 2)
                }
            }
            .frame(width: 56, height: 56)
            .overlay {
                RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(theme.displayName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.ink)
                Text(theme.blurb)
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? Color.coral : Color.inkTertiary)
        }
        .padding(ThemeSpacing.sm)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous)
                .strokeBorder(selected ? Color.coral : Color.line, lineWidth: selected ? 2 : 1)
        }
    }
}
