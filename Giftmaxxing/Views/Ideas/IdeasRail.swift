import SwiftUI
import GiftmaxxingCore

// Home's single discovery rail. Replaces the three that used to compete here
// (Gift galleries, Group gifts, Goes well together) — group gifts moved to
// Circles, and galleries and bundles are now the same thing: idea packs.
struct IdeasRail: View {
    var onSelect: (IdeaPack) -> Void
    var onSeeAll: () -> Void

    @ObservedObject private var loader = IdeasLoader.shared

    var body: some View {
        Group {
            if loader.packs.isEmpty {
                // Nothing curated yet (a fresh environment before
                // build-shelves.mjs has run) — show nothing rather than an
                // empty shelf.
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
                    HStack {
                        Label("Ideas", systemImage: "lightbulb.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Button("See all", action: onSeeAll)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.coral)
                    }
                    .padding(.horizontal, 14)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: ThemeSpacing.sm) {
                            ForEach(loader.interleaved) { pack in
                                Button { onSelect(pack) } label: {
                                    IdeaPackCard(pack: pack)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, ThemeSpacing.xs)
                .background(Color.surface)
            }
        }
        .task { await loader.loadIfNeeded() }
    }
}
