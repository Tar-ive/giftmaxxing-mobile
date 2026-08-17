import SwiftUI
import GiftmaxxingCore
import GiftmaxxingNetworking
import GiftmaxxingDesignSystem

// The Ideas see-all. Two ways to browse, because there are two ways people
// arrive: with a theme in mind (Packs) or with nothing in mind and a hope that
// we know their taste (For you).
struct IdeasView: View {
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var loader = IdeasLoader.shared

    @State private var mode: Mode = .packs
    @State private var picks: [Post] = []
    @State private var picksLoaded = false
    @State private var selectedPack: IdeaPack?
    @State private var selectedPost: Post?
    @State private var pickerPost: Post?

    enum Mode: String, CaseIterable {
        case packs = "Packs"
        case forYou = "For you"
    }

    private let columns = [
        GridItem(.flexible(), spacing: ThemeSpacing.sm),
        GridItem(.flexible(), spacing: ThemeSpacing.sm),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ThemeSpacing.md) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, ThemeSpacing.md)

                switch mode {
                case .packs: packsGrid
                case .forYou: forYouGrid
                }
            }
            .padding(.top, ThemeSpacing.sm)
            .padding(.bottom, 100)
        }
        .background(Color.cream)
        .navigationTitle("Ideas")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedPack) { pack in
            IdeaPackDetailView(pack: pack)
        }
        .sheet(item: $selectedPost) { post in
            PostDetailView(post: post)
        }
        .sheet(item: $pickerPost) { post in
            RecipientPickerSheet(posts: [post], source: "ideas")
        }
        .task {
            await loader.loadIfNeeded()
            await loadPicks()
        }
        .onChange(of: mode) { _, _ in
            Task { await loadPicks() }
        }
    }

    private var packsGrid: some View {
        LazyVGrid(columns: columns, spacing: ThemeSpacing.md) {
            ForEach(loader.interleaved) { pack in
                Button { selectedPack = pack } label: {
                    IdeaPackCard(pack: pack, width: nil)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, ThemeSpacing.md)
    }

    @ViewBuilder
    private var forYouGrid: some View {
        if picks.isEmpty {
            VStack(spacing: ThemeSpacing.sm) {
                if picksLoaded {
                    Text("Save a few things and this fills up.")
                        .font(.body)
                        .foregroundStyle(Color.inkSecondary)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 64)
        } else {
            LazyVGrid(columns: columns, spacing: ThemeSpacing.md) {
                ForEach(picks) { post in
                    pickCard(post)
                }
            }
            .padding(.horizontal, ThemeSpacing.md)
        }
    }

    private func pickCard(_ post: Post) -> some View {
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

            HStack {
                if post.product.price > 0 {
                    Text(post.product.price, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.coral)
                }
                Spacer()
                Button {
                    pickerPost = post
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

    // The same personalized path Maxi and Home use — taste centroid → S3
    // Vectors kNN — so all three surfaces agree on what "for you" means.
    private func loadPicks() async {
        guard mode == .forYou, picks.isEmpty else { return }
        defer { picksLoaded = true }
        guard let userId = authManager.userId, !userId.isEmpty else { return }
        let response = try? await APIClient.shared.fetchVectorRecommendations(
            userId: userId,
            limit: 24
        )
        picks = (response?.items ?? []).map(Post.init(vectorItem:))
    }
}
