import SwiftUI

// What the search page shows before you have typed anything.
//
// An empty search box with a blank page below it is the worst screen in any
// app: it asks a question and offers no way to answer. This gives two ways in —
// what you searched before, and the things people actually search for here —
// so the page is useful on arrival rather than only after a good guess.
struct SearchDiscoverPanel: View {
    @ObservedObject private var recents = RecentSearchStore.shared
    var onPick: (String) -> Void

    // Deliberately concrete. "Gifts" or "Popular" would be true of everything
    // on the page and lead nowhere in particular.
    private static let suggestions = [
        "Matcha set", "Cozy candle", "Instant camera", "Personalised jewellery",
        "Coffee grinder", "Skincare set", "Desk lamp", "Vinyl record player",
        "Board game", "Scrapbook kit", "Running gear", "Perfume",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.md) {
            if !recents.items.isEmpty {
                VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
                    HStack {
                        SectionHeader("Recent")
                        Spacer()
                        Button("Clear") { recents.clear() }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.coral)
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(recents.items, id: \.self) { term in
                            Button { onPick(term) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(term)
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(Color.ink)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(Color.surfaceSunken, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
                SectionHeader("Try searching for")
                FlowLayout(spacing: 8) {
                    ForEach(Self.suggestions, id: \.self) { term in
                        Button { onPick(term) } label: {
                            Text(term)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.ink)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background {
                                    Capsule().strokeBorder(Color.line, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            SectionHeader("Browse")
        }
        .padding(.horizontal, 14)
    }
}
