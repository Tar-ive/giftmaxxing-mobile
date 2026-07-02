import SwiftUI
import PhotosUI

// Search — iOS port of web/app/feed/search/page.tsx: People / Brands /
// Products / Visual tabs, brand-enriched matching, and photo-based visual
// search against the live kNN endpoint.
enum SearchTab: String, CaseIterable {
    case people = "People"
    case brands = "Brands"
    case products = "Products"
    case visual = "Visual"
}

@MainActor
final class SearchTabsViewModel: ObservableObject {
    @Published var query = ""
    @Published var tab: SearchTab = .products
    @Published var catalog: [Post] = []
    @Published var isLoadingCatalog = false

    // Visual search state (mirrors web vResults/vLoading/vError).
    @Published var visualResults: [VectorItem]?
    @Published var visualLoading = false
    @Published var visualError: String?
    @Published var queryImage: UIImage?

    private let api = APIClient.shared

    // People — web filters USERS by name/handle.
    var people: [(id: String, name: String, grad: GradientStyle)] {
        let t = query.trimmingCharacters(in: .whitespaces).lowercased()
        return SocialUsers.all
            .filter { $0.key != "you" }
            .map { (id: $0.key, name: $0.value.name, grad: $0.value.grad) }
            .filter { t.isEmpty || $0.name.lowercased().contains(t) || $0.id.contains(t) }
            .sorted { $0.name < $1.name }
    }

    // Products — web matches title/category/enriched brand.
    var products: [Post] {
        let t = query.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty { return Array(catalog.prefix(18)) }
        return catalog.filter { post in
            post.product.name.lowercased().contains(t)
                || (post.category ?? "").lowercased().contains(t)
                || BrandEnrichment.enrich(post: post).lowercased().contains(t)
        }
    }

    // Brands — web groups by enriched brand, sorted by count, top 20.
    var brands: [(brand: String, posts: [Post])] {
        let t = query.trimmingCharacters(in: .whitespaces).lowercased()
        var map: [String: (brand: String, posts: [Post])] = [:]
        for post in catalog {
            let brand = BrandEnrichment.enrich(post: post)
            if !t.isEmpty && !brand.lowercased().contains(t) { continue }
            let key = brand.lowercased()
            map[key, default: (brand: brand, posts: [])].posts.append(post)
        }
        return map.values
            .sorted { $0.posts.count > $1.posts.count }
            .prefix(20)
            .map { $0 }
    }

    func loadCatalog() async {
        guard catalog.isEmpty, !isLoadingCatalog else { return }
        isLoadingCatalog = true
        if let page = try? await api.fetchFeed(limit: 60) {
            catalog = page.posts
        }
        isLoadingCatalog = false
    }

    // Generation token: "Clear photo" (or a newer search) invalidates any
    // in-flight request, so late responses can't repopulate a cleared pane.
    private var searchGeneration = 0

    func runVisualSearch(with image: UIImage) async {
        searchGeneration += 1
        let generation = searchGeneration

        tab = .visual
        queryImage = image
        visualResults = nil
        visualError = nil
        visualLoading = true

        // Downscale before upload (Titan MM works fine at 512px; keeps the
        // payload small on cell connections).
        guard let jpeg = image.resized(maxDimension: 512).jpegData(compressionQuality: 0.8) else {
            visualError = "Couldn't read that image. Try a different one."
            visualLoading = false
            return
        }

        do {
            let response = try await api.fetchVisualSearch(imageBase64: jpeg.base64EncodedString())
            guard generation == searchGeneration else { return }
            visualResults = response.items ?? []
        } catch {
            guard generation == searchGeneration else { return }
            visualError = "Couldn't run visual search. Try a different image."
        }
        visualLoading = false
    }

    func clearVisual() {
        searchGeneration += 1
        queryImage = nil
        visualResults = nil
        visualError = nil
        visualLoading = false
    }
}

struct SearchTabsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = SearchTabsViewModel()
    @State private var selectedPost: Post?
    @State private var photoItem: PhotosPickerItem?
    @State private var showSourceDialog = false
    @State private var showCamera = false
    @State private var showLibrary = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search field + camera button (web: search input + photo upload)
                HStack(spacing: 8) {
                    SearchBar(
                        text: $viewModel.query,
                        placeholder: "Search gifts, brands, people...",
                        onSubmit: {}
                    )

                    Button {
                        // On a device: choose camera or library. No camera
                        // (simulator/iPad without one): straight to library.
                        if CameraPicker.isAvailable {
                            showSourceDialog = true
                        } else {
                            showLibrary = true
                        }
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.coral)
                            .frame(width: 42, height: 42)
                            .background(Color.coralSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("Visual search with a photo")
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)

                // Tabs (web TABS row)
                HStack(spacing: 6) {
                    ForEach(SearchTab.allCases, id: \.self) { tab in
                        Button {
                            viewModel.tab = tab
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(viewModel.tab == tab ? .white : Color.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(viewModel.tab == tab ? Color.ink : Color.cream)
                                .clipShape(Capsule())
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                ScrollView {
                    switch viewModel.tab {
                    case .people:
                        peopleList
                    case .brands:
                        brandsList
                    case .products:
                        productsGrid
                    case .visual:
                        visualSearchPane
                    }
                }
            }
            .background(Color.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Search")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
            }
            .sheet(item: $selectedPost) { post in
                PostDetailView(post: post)
            }
            .task {
                AnalyticsEngine.shared.trackScreenView(screen: "search")
                await viewModel.loadCatalog()
            }
            .onAppear {
                if let pending = appState.pendingSearchTab {
                    viewModel.tab = pending
                    appState.pendingSearchTab = nil
                }
                consumeCapture()
            }
            .onChange(of: appState.pendingSearchTab) { _, pending in
                if let pending {
                    viewModel.tab = pending
                    appState.pendingSearchTab = nil
                }
            }
            .onChange(of: appState.pendingCaptureImage) { _, _ in
                consumeCapture()
            }
            .onChange(of: appState.pendingCaptureNote) { _, _ in
                consumeCapture()
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await viewModel.runVisualSearch(with: image)
                    }
                    photoItem = nil
                }
            }
            .confirmationDialog("Search with a photo", isPresented: $showSourceDialog, titleVisibility: .visible) {
                Button("Take a photo") { showCamera = true }
                Button("Choose from library") { showLibrary = true }
                Button("Cancel", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    Task { await viewModel.runVisualSearch(with: image) }
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
        }
    }

    // Shared-in image (share extension / screenshots rail) → visual search.
    private func consumeCapture() {
        if let image = appState.pendingCaptureImage {
            appState.pendingCaptureImage = nil
            Task { await viewModel.runVisualSearch(with: image) }
        } else if let note = appState.pendingCaptureNote {
            appState.pendingCaptureNote = nil
            viewModel.tab = .visual
            viewModel.visualError = note
        }
    }

    // MARK: People

    private var peopleList: some View {
        LazyVStack(spacing: 0) {
            if viewModel.people.isEmpty {
                emptyNote("No people match \"\(viewModel.query)\".")
            }
            ForEach(viewModel.people, id: \.id) { person in
                HStack(spacing: 12) {
                    AvatarView(name: person.name, grad: person.grad, size: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(person.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ink)
                        Text("@\(person.id)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    NavigationLink {
                        ChallengeView()
                    } label: {
                        Text("Challenge")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.coral)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.coralSoft)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: Brands

    private var brandsList: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            if viewModel.isLoadingCatalog {
                ProgressView().frame(maxWidth: .infinity).padding(40)
            } else if viewModel.brands.isEmpty {
                emptyNote("No brands match \"\(viewModel.query)\".")
            }
            ForEach(viewModel.brands, id: \.brand) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(group.brand)
                            .font(.displaySmall)
                            .foregroundStyle(Color.ink)
                        Text("\(group.posts.count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.coral)
                            .clipShape(Capsule())
                        Spacer()
                    }
                    .padding(.horizontal, 14)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(group.posts.prefix(10)) { post in
                                Button {
                                    selectedPost = post
                                } label: {
                                    productTile(post, size: 110)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: Products

    private var productsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 12) {
            if viewModel.isLoadingCatalog {
                ProgressView().padding(40)
            } else if viewModel.products.isEmpty {
                emptyNote("No products match \"\(viewModel.query)\".")
                    .gridCellColumns(2)
            }
            ForEach(viewModel.products) { post in
                Button {
                    selectedPost = post
                } label: {
                    gridCard(post)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: Visual

    private var visualSearchPane: some View {
        VStack(spacing: 16) {
            if let queryImage = viewModel.queryImage {
                VStack(spacing: 10) {
                    Image(uiImage: queryImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    Button("Clear photo") {
                        viewModel.clearVisual()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.coral)
                }
                .padding(.top, 12)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.coral)
                    Text("Search with a photo")
                        .font(.displaySmall)
                        .foregroundStyle(Color.ink)
                    Text("Snap or upload a photo of something they'd love — I'll find visually similar gifts.")
                        .font(.bodyMedium)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if CameraPicker.isAvailable {
                        Button {
                            showCamera = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                Text("Take a photo")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.coral)
                            .clipShape(Capsule())
                        }
                    }

                    Button {
                        showLibrary = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle")
                            Text("Choose from library")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CameraPicker.isAvailable ? Color.coral : .white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(CameraPicker.isAvailable ? Color.coralSoft : Color.coral)
                        .clipShape(Capsule())
                    }
                }
                .padding(40)
            }

            if viewModel.visualLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Matching against the gift index…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }

            if let error = viewModel.visualError {
                emptyNote(error)
            }

            if let results = viewModel.visualResults {
                if results.isEmpty {
                    emptyNote("No visual matches found. Try a different image.")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 12) {
                        ForEach(results) { item in
                            visualResultCard(item)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Shared tiles

    private func productTile(_ post: Post, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                Color.gradient(for: post.product.grad)
                Text(post.product.emoji).font(.system(size: 28))
                if let image = post.product.image {
                    CachedAsyncImage(url: image, width: 300)
                }
            }
            .frame(width: size, height: size)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(post.product.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .frame(width: size, alignment: .leading)

            Text("$\(Int(post.product.price))")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.coral)
        }
    }

    private func gridCard(_ post: Post) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Color.gradient(for: post.product.grad)
                Text(post.product.emoji).font(.system(size: 40))
                if let image = post.product.image {
                    CachedAsyncImage(url: image, width: 400)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 170)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Text(post.product.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)

            HStack {
                Text(BrandEnrichment.enrich(post: post))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("$\(Int(post.product.price))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.coral)
                    .fixedSize()
            }
        }
    }

    private func visualResultCard(_ item: VectorItem) -> some View {
        Button {
            // Map the vector hit onto the post detail sheet via a synthesized post.
            selectedPost = Post(
                id: item.postId,
                user: item.author ?? "giftmaxxing",
                time: "",
                product: Product(
                    id: item.postId,
                    name: item.name ?? "Visual match",
                    brand: item.merchant ?? item.source ?? "Giftmaxxing",
                    price: item.price ?? 0,
                    grad: .coral,
                    emoji: "🎁",
                    image: item.image
                ),
                caption: item.reason ?? "",
                likes: 0,
                productUrl: item.productUrl ?? item.url
            )
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Color.gradient(for: .coral)
                    if let image = item.image {
                        CachedAsyncImage(url: image, width: 400)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Text(item.name ?? "Visual match")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)

                if let price = item.price, price > 0 {
                    Text("$\(Int(price))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.coral)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.bodyMedium)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(30)
    }
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return self }
        let scale = maxDimension / largest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
