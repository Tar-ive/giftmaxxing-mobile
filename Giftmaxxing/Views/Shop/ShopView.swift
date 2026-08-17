import SwiftUI
import GiftmaxxingCore
import GiftmaxxingNetworking
import GiftmaxxingDesignSystem

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
    // Social proof for the grid ("N saved") — the marketplace-style nudge
    // next to the price.
    var likes: Int = 0
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
                affiliateUrl: buyUrl,
                likes: post.likes
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

    // Masonry: two independent columns (marketplace style) — cards get varied
    // image heights, and each item goes to the currently-shorter column so the
    // columns stay balanced.
    private var masonryColumns: (left: [ShopItem], right: [ShopItem]) {
        var left: [ShopItem] = []
        var right: [ShopItem] = []
        var leftHeight = 0.0
        var rightHeight = 0.0
        for item in viewModel.filteredItems {
            let h = ShopItemCard.imageAspect(for: item)
            if leftHeight <= rightHeight {
                left.append(item)
                leftHeight += h
            } else {
                right.append(item)
                rightHeight += h
            }
        }
        return (left, right)
    }

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

                    // Birthday freebies — free stuff brands give out every
                    // birthday (Sephora/Starbucks/Denny's...), see
                    // BirthdayPerksSection.swift.
                    BirthdayPerksSection()

                    // Product grid — masonry (staggered columns, image-first)
                    let columns = masonryColumns
                    HStack(alignment: .top, spacing: 12) {
                        LazyVStack(spacing: 14) {
                            ForEach(columns.left) { item in
                                ShopItemCard(item: item) {
                                    viewModel.selectedItem = item
                                }
                            }
                        }
                        LazyVStack(spacing: 14) {
                            ForEach(columns.right) { item in
                                ShopItemCard(item: item) {
                                    viewModel.selectedItem = item
                                }
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

    // Stable per-item image height/width for the masonry stagger: hash of the
    // id picks from a small portrait-biased set, so the layout varies but any
    // given item always renders the same shape.
    static func imageAspect(for item: ShopItem) -> Double {
        let ratios: [Double] = [1.0, 1.12, 1.25, 1.33]
        var h: UInt64 = 5381
        for byte in item.id.utf8 { h = (h &* 33) &+ UInt64(byte) }
        return ratios[Int(h % UInt64(ratios.count))]
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Image — the block sizes ITSELF (Color.clear), and everything
                // else rides in an overlay. A `.fill` AsyncImage placed directly
                // in the ZStack reports the photo's intrinsic size to layout,
                // which inflated cells and shoved titles/prices onto the
                // neighboring grid column.
                Color.clear
                    .aspectRatio(1 / Self.imageAspect(for: item), contentMode: .fit)
                    .overlay {
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
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                // Info — marketplace-style: title, then a prominent price with
                // social proof beside it (the brand lives in the detail sheet;
                // dropping it here keeps the grid image-first and scannable).
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let price = item.price {
                            Text("$\(Int(price))")
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.coral)
                        } else {
                            Text("See price on Amazon")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.coral)
                        }
                        if item.likes > 0 {
                            Text("\(item.likes) saved")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ShopItemDetail: View {
    let item: ShopItem
    @Environment(\.dismiss) private var dismiss
    @State private var browserTarget: BrowserTarget?
    @State private var showListPicker = false
    @ObservedObject private var swipeLists = SwipeListStore.shared

    private var isAmazon: Bool {
        guard let url = item.affiliateUrl else { return false }
        return Affiliate.isAmazonUrl(url)
    }

    // Shop items ride the same gifting rails as feed posts (swipe lists and
    // gift pools both speak Post) — synthesize one from the catalog item.
    private var asPost: Post {
        Post(
            id: item.id,
            user: "giftmaxxing_shop",
            time: "",
            product: Product(
                id: item.id,
                name: item.title,
                brand: item.brand ?? "Giftmaxxing",
                price: item.price ?? 0,
                grad: item.grad,
                emoji: item.emoji,
                image: item.image
            ),
            caption: "",
            likes: 0,
            productUrl: item.affiliateUrl,
            category: item.category
        )
    }

    // Human-readable merchant for the buy button: the link's host without "www.".
    private func merchantName(for link: URL) -> String {
        let host = (link.host ?? "").lowercased()
        let name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return name.isEmpty ? "retailer site" : name
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Image
                    Color.clear
                        .frame(height: 300)
                        .overlay {
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
                        }
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

                        // Buy button — labeled for the ACTUAL retailer behind the
                        // link (Amazon-orange only for Amazon; other merchants get
                        // their own domain on a coral button). Amazon app when
                        // installed, in-app browser fallback (and click analytics)
                        // via the outbound router.
                        if let url = item.affiliateUrl, let link = URL(string: url) {
                            Button {
                                OutboundRouter.open(link, postId: item.id, source: "shop") {
                                    browserTarget = BrowserTarget(url: $0)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "cart.fill")
                                    Text(isAmazon ? "Buy on Amazon" : "Shop on \(merchantName(for: link))")
                                }
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(isAmazon ? Color(hex: "#FF9900") : Color.coral)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .sheet(item: $browserTarget) { target in
                                SafariView(url: target.url)
                                    .ignoresSafeArea()
                            }
                        }

                        // Gifting rail — file this find into a person's Gift
                        // Board. (Gift pools moved behind the Circles invite.)
                        Button {
                            showListPicker = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: swipeLists.contains(asPost)
                                      ? "checkmark" : "rectangle.stack.badge.plus")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(swipeLists.contains(asPost) ? "On board" : "Gift board")
                                    .font(.system(size: 13, weight: .bold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color.coral)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(Color.coralSoft)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        // The Associates disclosure only applies to Amazon links.
                        if isAmazon {
                            Text("As an Amazon Associate, giftmaxxing earns from qualifying purchases.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
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
            .sheet(isPresented: $showListPicker) {
                SwipeListPickerSheet(post: asPost)
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
