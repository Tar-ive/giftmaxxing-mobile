import SwiftUI

// Home rail: the user's own Gift Boards, one card per person/occasion. Boards
// live in Swipe → Gift Boards; this rail is the discoverability bridge — it
// appears once the first board exists and deep-links straight into a board.
struct GiftBoardsRail: View {
    @ObservedObject private var store = SwipeListStore.shared
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if !store.lists.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Your Gift Boards", systemImage: "rectangle.stack.fill")
                        .font(.labelBold)
                        .foregroundStyle(Color.ink)
                    Spacer()
                    Button {
                        appState.openBoardsHome()
                    } label: {
                        Text("See all")
                            .font(.bodySmall.weight(.semibold))
                            .foregroundStyle(Color.coral)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See all Gift Boards")
                }
                .padding(.horizontal, 14)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(store.lists) { list in
                            Button {
                                appState.openBoard(list.id)
                            } label: {
                                card(list)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                "\(list.name), \(list.posts.count) idea\(list.posts.count == 1 ? "" : "s")"
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 2)
                }
            }
            .padding(.vertical, 8)
            .background(Color.surface)
        }
    }

    private func card(_ list: SwipeList) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover collage — up to two item thumbnails, matching SwipeListRow.
            HStack(spacing: 2) {
                ForEach(Array(list.posts.prefix(2).enumerated()), id: \.offset) { _, post in
                    ZStack {
                        Color.gradient(for: post.product.grad)
                        if let image = post.product.image {
                            CachedAsyncImage(url: image, width: 300)
                        }
                    }
                    .frame(width: list.posts.count == 1 ? 140 : 69, height: 90)
                    .clipped()
                }
                if list.posts.isEmpty {
                    Image(systemName: "gift")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.coral)
                        .frame(width: 140, height: 90)
                        .background(Color.coralSoft)
                }
            }
            .frame(width: 140, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text("\(list.posts.count) idea\(list.posts.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
            .frame(width: 140, alignment: .leading)
        }
    }
}
