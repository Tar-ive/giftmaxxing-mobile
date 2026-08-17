import SwiftUI

struct CuratedJourneyRail: View {
    let onSelect: (CuratedGiftJourney) -> Void
    let onSeeAll: () -> Void

    private let store = CuratedGiftStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
                    Text("CURATED BY HAND")
                        .font(.caption.weight(.medium))
                        .tracking(0.5)
                        .foregroundStyle(Color.coral)
                    Text("Start with the idea")
                        .font(.title3.weight(.semibold))
                        .fontDesign(.rounded)
                        .foregroundStyle(Color.ink)
                }
                Spacer()
                Button("See all", action: onSeeAll)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.coral)
                    .frame(minHeight: ThemeSpacing.xl * 2)
                    .accessibilityLabel("See all curated gift guides")
            }
            .padding(.horizontal, ThemeSpacing.md)

            ScrollView(.horizontal) {
                LazyHStack(spacing: ThemeSpacing.sm) {
                    ForEach(store.catalog.journeys) { journey in
                        Button { onSelect(journey) } label: {
                            journeyCard(journey)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(journey.title)")
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, ThemeSpacing.md)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
        .padding(.vertical, ThemeSpacing.md)
        .background(Color.cream)
    }

    private func journeyCard(_ journey: CuratedGiftJourney) -> some View {
        let products = store.products(for: journey)
        return VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
            CachedAsyncImage(url: journey.images.first, width: 600, contentMode: .fit)
                .aspectRatio(3 / 4, contentMode: .fit)
                .background(Color.surfaceSunken)
                .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))

            Text(journey.title)
                .font(.headline)
                .foregroundStyle(Color.ink)
                .lineLimit(2)

            Text(products.isEmpty ? "Inspiration guide" : "\(products.count) verified matches")
                .font(.footnote)
                .foregroundStyle(Color.inkTertiary)
        }
        .containerRelativeFrame(.horizontal, count: 10, span: 7, spacing: ThemeSpacing.sm)
    }
}

struct CuratedJourneyListView: View {
    private let store = CuratedGiftStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(spacing: ThemeSpacing.md) {
                ForEach(store.catalog.journeys) { journey in
                    let products = store.products(for: journey)
                    NavigationLink(value: journey) {
                        HStack(spacing: ThemeSpacing.md) {
                            CachedAsyncImage(url: journey.images.first, width: 300, contentMode: .fit)
                                .frame(width: ThemeSpacing.xl * 4, height: ThemeSpacing.xl * 4)
                                .background(Color.surfaceSunken)
                                .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous))

                            VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
                                Text(journey.title)
                                    .font(.headline)
                                    .foregroundStyle(Color.ink)
                                Text(journey.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.inkSecondary)
                                    .lineLimit(2)
                                Text(products.isEmpty ? "Inspiration guide" : "\(products.count) verified matches")
                                    .font(.footnote)
                                    .foregroundStyle(Color.coral)
                            }
                            Spacer()
                        }
                        .padding(ThemeSpacing.sm)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(ThemeSpacing.md)
        }
        .background(Color.cream)
        .navigationTitle("Curated guides")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: CuratedGiftJourney.self) { CuratedJourneyDetailView(journey: $0) }
    }
}

struct CuratedJourneyDetailView: View {
    let journey: CuratedGiftJourney

    @State private var pickerPosts: PostBundle?
    @State private var browserTarget: BrowserTarget?
    @State private var selectionFeedback = false

    private let store = CuratedGiftStore.shared
    private var products: [CuratedGiftProduct] { store.products(for: journey) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ThemeSpacing.xl) {
                sourceGallery
                editorialNote

                if !products.isEmpty {
                    productSection
                }

                wrapSection
            }
            .padding(.bottom, ThemeSpacing.xl)
        }
        .background(Color.cream)
        .navigationTitle(journey.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pickerPosts) { bundle in
            RecipientPickerSheet(posts: bundle.posts, source: bundle.source)
        }
        .sheet(item: $browserTarget) { target in
            SafariView(url: target.url).ignoresSafeArea()
        }
        .sensoryFeedback(.selection, trigger: selectionFeedback)
    }

    private var sourceGallery: some View {
        TabView {
            ForEach(journey.images, id: \.self) { image in
                CachedAsyncImage(url: image, width: 900, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.surfaceSunken)
            }
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .background(Color.surfaceSunken)
    }

    private var editorialNote: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.sm) {
            Text(journey.subtitle)
                .font(.title3.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.ink)
            Text(journey.whySelected)
                .font(.body)
                .foregroundStyle(Color.inkSecondary)
            Link(destination: URL(string: journey.sourceUrl)!) {
                Label("View source post", systemImage: "arrow.up.right")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.coral)
        }
        .padding(.horizontal, ThemeSpacing.md)
    }

    private var productSection: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.sm) {
            sectionHeader("Products in the idea", detail: "Identity checked against the source slide")

            ForEach(products) { product in
                productRow(product)
            }

            Button {
                pickerPosts = PostBundle(posts: products.map(\.post), source: "curated-products")
                selectionFeedback.toggle()
            } label: {
                Label("Add all \(products.count) to a cart", systemImage: "bag.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityLabel("Add all verified products to a cart")
        }
        .padding(.horizontal, ThemeSpacing.md)
    }

    private var wrapSection: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.sm) {
            sectionHeader("Finish the gift", detail: "A verified wrap kit from the curation")

            ForEach(store.catalog.wrapKit) { product in
                productRow(product)
            }

            Button {
                pickerPosts = PostBundle(posts: store.wrapPosts, source: "curated-wrap-kit")
                selectionFeedback.toggle()
            } label: {
                Label("Add the wrap kit", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel("Add verified wrapping supplies to a cart")
        }
        .padding(.horizontal, ThemeSpacing.md)
    }

    private func productRow(_ product: CuratedGiftProduct) -> some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.sm) {
            HStack(alignment: .top, spacing: ThemeSpacing.sm) {
                CachedAsyncImage(url: product.image, width: 300)
                    .aspectRatio(4 / 5, contentMode: .fill)
                    .frame(width: ThemeSpacing.xl * 3)
                    .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous))

                VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
                    Text(product.name)
                        .font(.headline)
                        .foregroundStyle(Color.ink)
                    Text(product.merchant)
                        .font(.footnote)
                        .foregroundStyle(Color.inkTertiary)
                    if product.price > 0 {
                        Text(product.price, format: .currency(code: "USD"))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.coral)
                    }
                }
                Spacer()
            }

            Text(product.matchEvidence)
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)

            Text(product.capabilities.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Color.inkTertiary)

            HStack(spacing: ThemeSpacing.sm) {
                Button(product.purchaseLabel) { open(product) }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel("\(product.purchaseLabel) for \(product.name)")

                Button {
                    pickerPosts = PostBundle(posts: [product.post], source: "curated-product")
                    selectionFeedback.toggle()
                } label: {
                    Image(systemName: "bag.badge.plus")
                        .frame(minWidth: ThemeSpacing.xl * 2, minHeight: ThemeSpacing.xl * 2)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityLabel("Add \(product.name) to a cart")
            }
        }
        .padding(ThemeSpacing.md)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
        .cardElevation()
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
            Text(title)
                .font(.title3.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.ink)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(Color.inkTertiary)
        }
    }

    private func open(_ product: CuratedGiftProduct) {
        guard let url = URL(string: product.productUrl) else { return }
        OutboundRouter.open(url, postId: product.post.id, source: "curated-pilot") {
            browserTarget = BrowserTarget(url: $0)
        }
    }

    private struct PostBundle: Identifiable {
        let posts: [Post]
        let source: String
        var id: String { source + posts.map(\.id).joined(separator: "|") }
    }
}
