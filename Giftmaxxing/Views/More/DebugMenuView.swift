import SwiftUI

// The operator's design bench. Only reachable from an allowlisted account —
// the row that opens it does not render for anyone else.
struct DebugMenuView: View {
    @ObservedObject private var session = DebugSessionManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ThemeSpacing.lg) {
                section("Design variant", "Changes the Create tab, the Circles icons and the accent. Everyone else always sees A.") {
                    ForEach(DesignVariant.allCases) { variant in
                        Button {
                            withAnimation(.snappy) { session.variant = variant }
                        } label: {
                            VariantRow(variant: variant, selected: session.variant == variant)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Variants change the Create tab, the Circles icons and the accent. The feed is locked to the masonry grid for everyone. Themes live in Appearance.")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
            }
            .padding(ThemeSpacing.md)
        }
        .background(Color.cream)
        .navigationTitle("Design bench")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        _ blurb: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.inkTertiary)
                .textCase(.uppercase)
            Text(blurb)
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .padding(.bottom, 2)
            content()
        }
    }
}

private struct VariantRow: View {
    let variant: DesignVariant
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: ThemeSpacing.sm) {
            Circle()
                .fill(accentPreview)
                .frame(width: 18, height: 18)
                .overlay { Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1) }
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(variant.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.ink)
                Text(variant.blurb)
                    .font(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.coral : Color.inkTertiary)
        }
        .padding(ThemeSpacing.sm)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous)
                .strokeBorder(selected ? Color.coral : Color.line, lineWidth: selected ? 2 : 1)
        }
    }

    private var accentPreview: Color {
        guard let hex = variant.accentHex else { return Color.coral }
        return Color(hex: hex.dark)
    }
}
