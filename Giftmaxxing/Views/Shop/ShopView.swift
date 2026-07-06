import SwiftUI

struct ShopItem: Identifiable {
    let id: String
    var title: String
    var brand: String?
    var price: Double?
    var image: String?
    var category: String?
    var emoji: String
    var grad: GradientStyle
    var affiliateUrl: String?
}

@MainActor
final class ShopViewModel: ObservableObject {
    // Starts on the sample grid only until the live catalog answers — Shop
    // shows REAL products with real photos, not emoji placeholders.
    @Published var items: [ShopItem] = ShopItem.samples
    @Published var selectedCategory: String?
    @Published var selectedItem: ShopItem?
    @Published var isLive = false

    var categories: [String] {
        let cats = Set(items.compactMap { $0.category })
        return Array(cats).sorted()
    }

    var filteredItems: [ShopItem] {
        guard let category = selectedCategory else { return items }
        return items.filter { $0.category == category }
    }

    // Curate from the live feed: only items with a real photo make the shop
    // grid, deduped by product, capped per category for a browsable spread.
    func loadCatalog() async {
        guard !isLive else { return }
        guard let page = try? await APIClient.shared.fetchFeed(limit: 60) else { return }
        var seen = Set<String>()
        var byCategory: [String: Int] = [:]
        var live: [ShopItem] = []
        for post in page.posts {
            guard let image = post.product.image, !image.isEmpty else { continue }
            guard seen.insert(post.product.name).inserted else { continue }
            let category = (post.category ?? "Gifts").capitalized
            if byCategory[category, default: 0] >= 12 { continue }
            byCategory[category, default: 0] += 1
            let buyUrl = post.productUrl ?? post.url
            live.append(ShopItem(
                id: post.id,
                title: post.product.name,
                brand: BrandEnrichment.enrich(post: post),
                price: post.product.price > 0 ? post.product.price : nil,
                image: image,
                category: category,
                emoji: post.product.emoji,
                grad: post.product.grad,
                affiliateUrl: buyUrl
            ))
        }
        guard live.count >= 8 else { return } // thin catalog → keep samples
        items = live
        isLive = true
        if let selectedCategory, !categories.contains(selectedCategory) {
            self.selectedCategory = nil
        }
    }
}

struct ShopView: View {
    @StateObject private var viewModel = ShopViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Category filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            CategoryPill(
                                label: "All",
                                isSelected: viewModel.selectedCategory == nil,
                                action: { viewModel.selectedCategory = nil }
                            )
                            ForEach(viewModel.categories, id: \.self) { cat in
                                CategoryPill(
                                    label: cat,
                                    isSelected: viewModel.selectedCategory == cat,
                                    action: { viewModel.selectedCategory = cat }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    // Affiliate disclosure
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                        Text("As an Amazon Associate, giftmaxxing earns from qualifying purchases.")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                    // Product grid
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(viewModel.filteredItems) { item in
                            ShopItemCard(item: item) {
                                viewModel.selectedItem = item
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color.surface)
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.large)
            .task { await viewModel.loadCatalog() }
            .refreshable {
                viewModel.isLive = false
                await viewModel.loadCatalog()
            }
            .sheet(item: $viewModel.selectedItem) { item in
                ShopItemDetail(item: item)
            }
        }
    }
}

struct CategoryPill: View {
    let label: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? .white : Color.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.coral : Color.cream)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ShopItemCard: View {
    let item: ShopItem
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Image
                ZStack {
                    Color.gradient(for: item.grad)

                    Text(item.emoji)
                        .font(.system(size: 36))

                    if let image = item.image, let url = URL(string: image) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                        }
                    }

                    // Category badge
                    if let category = item.category {
                        VStack {
                            HStack {
                                Text(category)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.black.opacity(0.55))
                                    .clipShape(Capsule())
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(8)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)

                    if let brand = item.brand {
                        Text(brand)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    if let price = item.price {
                        Text("$\(Int(price))")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.coral)
                    } else {
                        Text("See price on Amazon")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.coral)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct ShopItemDetail: View {
    let item: ShopItem
    @Environment(\.dismiss) private var dismiss
    @State private var browserTarget: BrowserTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Image
                    ZStack {
                        Color.gradient(for: item.grad)
                        Text(item.emoji)
                            .font(.system(size: 80))
                        if let image = item.image, let url = URL(string: image) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                }
                            }
                        }
                    }
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.ink)

                        if let brand = item.brand {
                            Text(brand)
                                .font(.bodyMedium)
                                .foregroundStyle(.secondary)
                        }

                        if let price = item.price {
                            Text("$\(Int(price))")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color.coral)
                        }

                        Divider()

                        // Buy button — Amazon app when installed, in-app browser
                        // fallback (and click analytics) via the outbound router.
                        if let url = item.affiliateUrl, let link = URL(string: url) {
                            Button {
                                OutboundRouter.open(link, postId: item.id, source: "shop") {
                                    browserTarget = BrowserTarget(url: $0)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "cart.fill")
                                    Text("Buy on Amazon")
                                }
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(hex: "#FF9900"))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .sheet(item: $browserTarget) { target in
                                SafariView(url: target.url)
                                    .ignoresSafeArea()
                            }
                        }

                        // Affiliate note
                        Text("As an Amazon Associate, giftmaxxing earns from qualifying purchases.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

extension ShopItem {
    static let samples: [ShopItem] = [
        ShopItem(id: "s1", title: "Mini Instant Camera", brand: "Halo", price: 79, category: "Tech", emoji: "📷", grad: .sky),
        ShopItem(id: "s2", title: "Matcha Starter Kit", brand: "Kettl", price: 54, category: "Food & Drink", emoji: "🍵", grad: .sage),
        ShopItem(id: "s3", title: "Soy Candle — Fig & Oud", brand: "Ember", price: 24, category: "Home", emoji: "🕯️", grad: .peach),
        ShopItem(id: "s4", title: "Eau de Parfum 50ml", brand: "Dusk", price: 88, category: "Beauty", emoji: "🌸", grad: .rose),
        ShopItem(id: "s5", title: "Vinyl — Midnight Hours", brand: "Lowtide", price: 32, category: "Music", emoji: "🎶", grad: .lilac),
        ShopItem(id: "s6", title: "Sunset Projector Lamp", brand: "Glow", price: 39, category: "Home", emoji: "🌅", grad: .coral),
        ShopItem(id: "s7", title: "Linen Daily Journal", brand: "Margin", price: 22, category: "Stationery", emoji: "📔", grad: .butter),
        ShopItem(id: "s8", title: "Wireless Buds Pro", brand: "Aera", price: 149, category: "Tech", emoji: "🎧", grad: .lilac),
    ]
}
