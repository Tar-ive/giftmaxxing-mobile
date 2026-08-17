import SwiftUI
import GiftmaxxingCore

// Tier 1 — the macro theme bar, as capsule pills.
//
// Pills rather than underlined text because this row PINS to the top of the
// screen once you scroll (the search row above it collapses away). An underline
// needs the text baseline to read as a selection; a filled capsule reads at a
// glance against whatever product photography has scrolled underneath it.
struct FeedThemeBar: View {
    let themes: [FeedTheme]
    @Binding var selection: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(themes) { theme in
                        let active = theme.id == selection
                        Button {
                            withAnimation(.snappy(duration: 0.25)) { selection = theme.id }
                        } label: {
                            Text(theme.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(active ? Color.onPrimary : Color.ink)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background {
                                    if active { Capsule().fill(Color.ink) }
                                    else { Capsule().fill(Color.surfaceSunken) }
                                }
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: active)
                        .id(theme.id)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
            }
            .onChange(of: selection) { _, id in
                // The pinned bar has to follow the selection or the active
                // category ends up scrolled off its own row.
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

// Tier 2 — micro tags for the active theme.
//
// Four visible plus a Filter pill (progressive disclosure): fifteen chips in a
// scroller is a menu nobody reads, and the ones past the fold may as well not
// exist. The full taxonomy lives in the sheet behind "Filter".
struct FeedTagBar: View {
    let tags: [FeedTag]
    @Binding var selection: String?
    var onOpenFilter: () -> Void

    /// Top N inline; the rest are reachable through the sheet.
    private static let visibleCount = 4

    private var inlineTags: [FeedTag] {
        // A selected tag from beyond the fold is pulled forward, otherwise
        // tapping it in the sheet would appear to do nothing up here.
        var shown = Array(tags.prefix(Self.visibleCount))
        if let selection, !shown.contains(where: { $0.id == selection }),
           let selected = tags.first(where: { $0.id == selection }) {
            shown.removeLast()
            shown.insert(selected, at: 0)
        }
        return shown
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", active: selection == nil) { selection = nil }

                ForEach(inlineTags) { tag in
                    chip(title: tag.title, active: selection == tag.id) {
                        selection = selection == tag.id ? nil : tag.id
                    }
                }

                if tags.count > Self.visibleCount {
                    Button(action: onOpenFilter) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("All filters")
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 36)
        // Edge fade instead of a container: it says "there's more" without a
        // border or an arrow, and keeps the bar visually weightless.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private func chip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Color.onPrimary : Color.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    // Only the ACTIVE chip gets a crisp tint. Inactive chips
                    // stay on a soft translucent fill so the secondary bar never
                    // competes with the products behind it.
                    if active {
                        Capsule().fill(Color.coral)
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                    }
                }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: active)
    }
}

// The full taxonomy, when four chips aren't enough.
struct FeedFilterSheet: View {
    let theme: FeedTheme
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ThemeSpacing.sm) {
                    SectionHeader(theme.title)

                    FlowLayout(spacing: 8) {
                        tagChip(id: nil, title: "All")
                        ForEach(theme.tags) { tag in
                            tagChip(id: tag.id, title: tag.title)
                        }
                    }
                }
                .padding(ThemeSpacing.md)
            }
            .background(Color.cream)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func tagChip(id: String?, title: String) -> some View {
        let active = selection == id
        return Button {
            selection = id
            dismiss()
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? Color.onPrimary : Color.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background {
                    if active { Capsule().fill(Color.coral) }
                    else { Capsule().fill(Color.surfaceSunken) }
                }
        }
        .buttonStyle(.plain)
    }
}
