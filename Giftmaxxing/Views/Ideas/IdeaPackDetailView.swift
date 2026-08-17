import SwiftUI
import GiftmaxxingCore
import GiftmaxxingDesignSystem

// A pack, opened. Two ways out: take the whole thing for one person, or pick
// the pieces you want. Bundles support both (one item per slot is the pairing's
// intent); galleries are a shelf, so only per-item makes sense there.
struct IdeaPackDetailView: View {
    let pack: IdeaPack

    @State private var pickerPosts: [Post]?
    @State private var selectedPost: Post?
    @State private var boardPickerPost: Post?

    private let columns = [
        GridItem(.flexible(), spacing: ThemeSpacing.sm),
        GridItem(.flexible(), spacing: ThemeSpacing.sm),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ThemeSpacing.lg) {
                header

                ForEach(pack.sections) { section in
                    VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
                        if let label = section.label {
                            HStack(spacing: 6) {
                                if let emoji = section.emoji { Text(emoji) }
                                Text(label)
                                    .font(.title3.weight(.semibold))
                                    .fontDesign(.rounded)
                                    .foregroundStyle(Color.ink)
                            }
                        }
                        LazyVGrid(columns: columns, spacing: ThemeSpacing.sm) {
                            ForEach(section.items) { post in
                                itemCard(post)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, ThemeSpacing.md)
            .padding(.bottom, 120)
        }
        .background(Color.cream)
        .navigationTitle(pack.kind == .bundle ? "Goes together" : pack.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if pack.supportsWholePackAdd {
                wholePackBar
            }
        }
        .sheet(item: Binding(
            get: { pickerPosts.map(PostBundle.init) },
            set: { pickerPosts = $0?.posts }
        )) { bundle in
            RecipientPickerSheet(
                posts: bundle.posts,
                source: "idea-pack"
            )
        }
        .sheet(item: $selectedPost) { post in
            PostDetailView(post: post)
        }
        .sheet(item: $boardPickerPost) { post in
            SwipeListPickerSheet(post: post)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
            Text(pack.title)
                .font(.title2.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.ink)
            if let why = pack.why {
                Text(why)
                    .font(.subheadline)
                    .foregroundStyle(Color.inkSecondary)
            }
            Text("\(pack.subtitle) · \(pack.itemCount) idea\(pack.itemCount == 1 ? "" : "s")")
                .font(.footnote)
                .foregroundStyle(Color.inkTertiary)
        }
        .padding(.top, ThemeSpacing.xs)
    }

    private var wholePackBar: some View {
        VStack(spacing: 4) {
            Button {
                pickerPosts = pack.representativeItems
            } label: {
                Text("Add all \(pack.representativeItems.count) to a cart")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            Text("One from each — swap any of them after.")
                .font(.captionMedium)
                .foregroundStyle(Color.inkTertiary)
        }
        .padding(.horizontal, ThemeSpacing.md)
        .padding(.top, ThemeSpacing.xs)
        .padding(.bottom, ThemeSpacing.sm)
        .background(.regularMaterial)
    }

    private func itemCard(_ post: Post) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Color.gradient(for: post.product.grad)
                if let image = post.product.image {
                    CachedAsyncImage(url: image, width: 400)
                }
            }
            .aspectRatio(1, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous))
            .onTapGesture { selectedPost = post }

            Text(post.product.name)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: ThemeSpacing.xs) {
                if post.product.price > 0 {
                    Text(post.product.price, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.coral)
                }
                Spacer()
                Button {
                    boardPickerPost = post
                } label: {
                    Image(systemName: "bookmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save \(post.product.name) to a Gift Board")

                Button {
                    pickerPosts = [post]
                } label: {
                    Image(systemName: "bag.badge.plus")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.coral)
                        .frame(width: 44, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(post.product.name) to a cart")
            }
        }
    }

    // Identifiable wrapper so an array can drive `.sheet(item:)`.
    private struct PostBundle: Identifiable {
        let posts: [Post]
        var id: String { posts.map(\.id).joined(separator: "|") }
    }
}
