import SwiftUI
import SwiftData

enum ProductReliabilityVote: String, Codable, CaseIterable {
    case reliable = "reliability_reliable"
    case questionable = "reliability_questionable"

    var title: String { self == .reliable ? "Reliable" : "Questionable" }
    var symbol: String { self == .reliable ? "checkmark.shield.fill" : "questionmark.diamond.fill" }
}

@MainActor
final class SwipeViewModel: ObservableObject {
    @Published var cards: [Post] = []
    @Published var currentIndex = 0
    @Published var isLoading = false
    @Published var yesCount = 0
    @Published var noCount = 0
    @Published var offset: CGSize = .zero
    @Published var isSwiping = false
    @Published private(set) var lifetimeSwipeCount: Int
    @Published private(set) var reliabilityVotes: [String: ProductReliabilityVote]
    @Published private(set) var reliabilityPromptCardId: String?

    private let api = APIClient.shared
    private let analytics = AnalyticsEngine.shared
    private var cursor: String?
    private var recommendationIds: [String: String] = [:]
    private var attributions: [String: String] = [:]
    private var ranks: [String: Int] = [:]
    private var cardShownAt = Date()
    private(set) var dragStartTime: Date?
    private(set) var userId: String?
    var recipientSegment = "self"

    private let defaults: UserDefaults
    private var identity = InteractionQueue.anonymousUserId
    private var lastReliabilityPromptAt: Date?
    private static let legacySwipeCountKey = "gm.swipeLifetimeCount"
    private static let legacyReliabilityVotesKey = "gm.productReliabilityVotes"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lifetimeSwipeCount = defaults.integer(forKey: Self.legacySwipeCountKey)
        reliabilityVotes = (try? defaults.data(forKey: Self.legacyReliabilityVotesKey)
            .map { try JSONDecoder().decode([String: ProductReliabilityVote].self, from: $0) }) ?? [:]
    }

    var currentCard: Post? { cards.indices.contains(currentIndex) ? cards[currentIndex] : nil }
    var choices: Int { yesCount + noCount }
    func shouldRequestReliability(for card: Post) -> Bool {
        reliabilityPromptCardId == card.id
    }

    func configure(userId: String?) {
        self.userId = userId
        identity = userId ?? InteractionQueue.anonymousUserId
        let scopedCount = defaults.object(forKey: swipeCountKey) as? Int
        lifetimeSwipeCount = scopedCount ?? defaults.integer(forKey: Self.legacySwipeCountKey)
        reliabilityVotes = decodeVotes(forKey: reliabilityVotesKey)
        if reliabilityVotes.isEmpty {
            reliabilityVotes = decodeVotes(forKey: Self.legacyReliabilityVotesKey)
        }
        lastReliabilityPromptAt = defaults.object(forKey: reliabilityPromptKey) as? Date
        reliabilityPromptCardId = nil
    }

    func loadCards(reset: Bool = true) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if reset {
            cards = []
            currentIndex = 0
            yesCount = 0
            noCount = 0
            cursor = nil
            recommendationIds = [:]
            attributions = [:]
            ranks = [:]
        }

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "swipeScreenshotMode") {
            cards = Array(CuratedGiftStore.shared.challengeProducts.prefix(30))
            currentIndex = 0
            offset = .zero
            showCurrentCard()
            return
        }
        #endif

        let recent = Array(cards.suffix(30).map(\.id))
        let remote = try? await api.fetchChallengeLearningDeck(
            profileIds: userId.map { ["taste:\($0)"] } ?? [],
            cursor: cursor,
            limit: 30,
            excludeItemIds: recent
        )
        if let remote, !remote.posts.isEmpty {
            let existing = Set(cards.map(\.id))
            let fresh = remote.posts.filter { !existing.contains($0.id) }
            cards.append(contentsOf: fresh.isEmpty ? remote.posts : fresh)
            cursor = remote.cursor
            remote.posts.forEach { recommendationIds[$0.id] = remote.recommendationId }
            attributions.merge(remote.attributions) { _, new in new }
            ranks.merge(remote.ranks) { _, new in new }
        } else {
            appendCuratedFallback()
        }
        if reset { showCurrentCard() }
    }

    func loadMoreIfNeeded() async {
        guard currentIndex >= cards.count - 6 else { return }
        if cursor == nil { cursor = nil }
        await loadCards(reset: false)
    }

    func loadSurprise() async {
        guard !isLoading else { return }
        cards = Array(CuratedGiftStore.shared.challengeProducts.shuffled())
        cursor = nil
        recommendationIds = [:]
        attributions = [:]
        ranks = [:]
        currentIndex = 0
        yesCount = 0
        noCount = 0
        offset = .zero
        showCurrentCard()
        analytics.trackScreenView(screen: "swipe_surprise")
    }

    func onDragStart() { dragStartTime = Date() }

    func cancelDrag(translation: CGSize) {
        if let card = currentCard, let start = dragStartTime {
            let distance = hypot(Double(translation.width), Double(translation.height))
            if distance > 30 {
                analytics.trackSwipeHesitation(
                    postId: card.id,
                    dragDistance: distance,
                    dragDurationMs: Date().timeIntervalSince(start) * 1000
                )
            }
        }
        dragStartTime = nil
        withAnimation(.spring(response: 0.3)) { offset = .zero }
    }

    func onHorizontalDragEnd(_ translation: CGSize, velocity: CGSize, context: ModelContext?) {
        if translation.width > 100 {
            swipeRight(velocity: Double(velocity.width), context: context)
        } else if translation.width < -100 {
            swipeLeft(velocity: Double(velocity.width), context: context)
        } else {
            cancelDrag(translation: translation)
        }
    }

    func swipeRight(velocity: Double = 500, context: ModelContext? = nil) {
        guard !isSwiping, let card = currentCard else { return }
        isSwiping = true
        yesCount += 1
        recordSwipeDecision()
        SwipeListStore.shared.addToMyGiftIdeas(card)
        record(.like, card: card, type: "like")
        analytics.trackSwipeRight(postId: card.id, velocity: abs(velocity), position: currentIndex)
        withAnimation(.spring(response: 0.38)) { offset = CGSize(width: 520, height: 0) }
        advance()
    }

    func swipeLeft(velocity: Double = 500, context: ModelContext? = nil) {
        guard !isSwiping, let card = currentCard else { return }
        isSwiping = true
        noCount += 1
        recordSwipeDecision()
        record(.hide, card: card, type: "hide")
        analytics.trackSwipeLeft(postId: card.id, velocity: abs(velocity), position: currentIndex)
        withAnimation(.spring(response: 0.38)) { offset = CGSize(width: -520, height: 0) }
        advance()
    }

    private func appendCuratedFallback() {
        let source = CuratedGiftStore.shared.challengeProducts
        let recent = Set(cards.suffix(min(cards.count, source.count / 2)).map(\.id))
        let batch = source.filter { !recent.contains($0.id) }.shuffled()
        cards.append(contentsOf: batch.isEmpty ? source.shuffled() : batch)
    }

    private func record(_ kind: TasteEvent.Kind, card: Post, type: String) {
        let decisionMs = Date().timeIntervalSince(cardShownAt) * 1000
        Task {
            let signals = TasteSignals.extract(from: card)
            let scale: Double = decisionMs < 1200 ? 1.3 : decisionMs > 6000 ? 0.85 : 1
            await TasteProfileStore.shared.record(TasteEvent(
                kind: kind, postId: card.id, author: card.user, price: card.product.price,
                vibes: signals.vibes, category: signals.category,
                giftType: card.giftType ?? "product", weightScale: scale
            ))
            let recommendationId = recommendationIds[card.id]
            await InteractionQueue.shared.enqueue(
                userId: userId,
                targetId: card.id,
                type: recommendationId == nil ? type : (type == "like" ? "challenge_yes" : "challenge_no"),
                data: [
                    "giftType": card.giftType ?? "product",
                    "decisionMs": String(Int(decisionMs)),
                    "recipientSegment": recipientSegment,
                ],
                recommendationId: recommendationId,
                attributionToken: attributions[card.id],
                position: ranks[card.id],
                forceMixer: true
            )
        }
    }

    func recordReliability(_ vote: ProductReliabilityVote, card: Post) {
        guard reliabilityVotes[card.id] == nil else { return }
        reliabilityVotes[card.id] = vote
        if let data = try? JSONEncoder().encode(reliabilityVotes) {
            defaults.set(data, forKey: reliabilityVotesKey)
        }
        reliabilityPromptCardId = nil
        analytics.trackProductReliabilityVote(
            postId: card.id,
            vote: vote.title.lowercased(),
            swipeCount: lifetimeSwipeCount
        )
        Task {
            await InteractionQueue.shared.enqueue(
                userId: userId,
                targetId: card.id,
                type: vote.rawValue,
                data: [
                    "label": vote.title.lowercased(),
                    "swipeCount": String(lifetimeSwipeCount),
                    "labelSource": "post_5_swipe_poll",
                ],
                recommendationId: recommendationIds[card.id],
                attributionToken: attributions[card.id],
                position: ranks[card.id],
                forceMixer: true
            )
        }
    }

    private func recordSwipeDecision() {
        lifetimeSwipeCount += 1
        defaults.set(lifetimeSwipeCount, forKey: swipeCountKey)
    }

    private func advance() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { [weak self] in
            guard let self else { return }
            currentIndex += 1
            offset = .zero
            isSwiping = false
            dragStartTime = nil
            if currentIndex >= cards.count { appendCuratedFallback() }
            showCurrentCard()
            Task { await self.loadMoreIfNeeded() }
        }
    }

    private func showCurrentCard() {
        cardShownAt = Date()
        guard let card = currentCard else { return }
        reliabilityPromptCardId = nil
        if ReliabilityPromptPolicy.canPrompt(
            completedSwipes: lifetimeSwipeCount,
            lastPromptAt: lastReliabilityPromptAt,
            hasVote: reliabilityVotes[card.id] != nil
        ) {
            let now = Date()
            lastReliabilityPromptAt = now
            defaults.set(now, forKey: reliabilityPromptKey)
            reliabilityPromptCardId = card.id
        }
        analytics.trackCardShown(postId: card.id, position: currentIndex, totalCards: cards.count)
        let urls = cards[currentIndex..<min(cards.count, currentIndex + 5)].compactMap { $0.product.image }
        Task { await ImageLoader.shared.prefetch(urls: urls, width: 800) }
    }

    private var storageSuffix: String { identity }
    private var swipeCountKey: String { "gm.swipeLifetimeCount.\(storageSuffix)" }
    private var reliabilityVotesKey: String { "gm.productReliabilityVotes.\(storageSuffix)" }
    private var reliabilityPromptKey: String { "gm.reliabilityPromptAt.\(storageSuffix)" }

    private func decodeVotes(forKey key: String) -> [String: ProductReliabilityVote] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: ProductReliabilityVote].self, from: data)) ?? [:]
    }
}

struct SwipeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = SwipeViewModel()
    @State private var context: GiftContext = .me
    @State private var details: Post?

    private enum GiftContext: String, CaseIterable {
        case me = "My taste"
        case people = "Friends"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contextPicker
                ChallengeInviteRail()
                if context == .people {
                    PeopleHubView()
                } else {
                    deck
                }
            }
            .background(context == .me ? Color.black : Color.cream)
            .navigationTitle("Swipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(context == .me ? .dark : .light, for: .navigationBar)
            .toolbarBackground(context == .me ? Color.black : Color.cream, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Swipe").font(.headline).foregroundStyle(context == .me ? .white : Color.ink)
                }
                if context == .me {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Task { await viewModel.loadSurprise() } } label: {
                            Image(systemName: "dice.fill").foregroundStyle(Color.coral)
                        }
                        .accessibilityLabel("Surprise me")
                    }
                }
            }
        }
        .sheet(item: $details) { SwipeProductDetails(post: $0) }
        .onChange(of: context) { _, value in
            if value == .me { Task { await viewModel.loadCards() } }
            else { AnalyticsEngine.shared.trackScreenView(screen: "swipe_people") }
        }
        .task(id: authManager.userId) {
            viewModel.configure(userId: authManager.userId)
            viewModel.recipientSegment = "self"
            if viewModel.cards.isEmpty {
                AnalyticsEngine.shared.trackScreenView(screen: "swipe")
                await viewModel.loadCards()
            }
        }
        .onAppear { appState.suppressMaxiFAB() }
        .onDisappear { appState.unsuppressMaxiFAB() }
    }

    private var contextPicker: some View {
        HStack(spacing: 4) {
            ForEach(GiftContext.allCases, id: \.self) { item in
                Button { context = item } label: {
                    Text(item.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(context == item
                            ? (item == .me ? Color.black : Color.ink)
                            : (context == .me ? Color.white.opacity(0.64) : Color.secondary))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(context == item ? Color.white : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(context == .me ? Color.white.opacity(0.14) : Color.ink.opacity(0.08), in: Capsule())
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    @ViewBuilder private var deck: some View {
        if viewModel.cards.isEmpty && viewModel.isLoading {
            ProgressView("Finding curated products…")
                .tint(.white).foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let card = viewModel.currentCard {
            VStack(spacing: 8) {
                learningBanner
                GeometryReader { proxy in
                    VStack(spacing: ThemeSpacing.sm) {
                        SwipeCardView(
                            post: card,
                            requestsReliability: viewModel.shouldRequestReliability(for: card),
                            onReliabilityVote: { viewModel.recordReliability($0, card: card) },
                            onDetails: { details = card }
                        )
                        .id(card.id)
                        .frame(height: max(0, proxy.size.height - 94))
                        .offset(viewModel.offset)
                        .rotationEffect(.degrees(Double(viewModel.offset.width) / 22))
                        .gesture(cardGesture)
                        actions
                    }
                    .padding(.horizontal, ThemeSpacing.sm)
                }
            }
            .padding(.bottom, 2)
        } else {
            Button("Reload curated products") { Task { await viewModel.loadCards() } }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var learningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .frame(width: 38, height: 38)
                .background(Color.red.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Learning your type").font(.subheadline.weight(.bold))
                Text(viewModel.yesCount < 10
                     ? "Like \(10 - viewModel.yesCount) more to sharpen your picks"
                     : "Your taste profile is getting smarter")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(viewModel.choices)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 12)
    }

    private var actions: some View {
        HStack(spacing: 84) {
            swipeButton("xmark", color: .white) { viewModel.swipeLeft(context: modelContext) }
            swipeButton("heart.fill", color: .red) { viewModel.swipeRight(context: modelContext) }
        }
    }

    private func swipeButton(_ symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 30, weight: .heavy)).foregroundStyle(color)
                .frame(width: 72, height: 72)
                .background(.black.opacity(0.65), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.18)))
        }
        .disabled(viewModel.isSwiping)
    }

    private var cardGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if viewModel.dragStartTime == nil { viewModel.onDragStart() }
                viewModel.offset = value.translation
            }
            .onEnded { value in
                if value.translation.height < -75,
                   abs(value.translation.height) > abs(value.translation.width) {
                    details = viewModel.currentCard
                    viewModel.cancelDrag(translation: value.translation)
                } else {
                    viewModel.onHorizontalDragEnd(value.translation, velocity: value.velocity, context: modelContext)
                }
            }
    }
}

struct SwipeCardView: View {
    let post: Post
    let requestsReliability: Bool
    var onReliabilityVote: (ProductReliabilityVote) -> Void
    var onDetails: () -> Void
    @State private var photoIndex = 0

    private var photos: [String] { post.product.gallery }

    var body: some View {
        ZStack(alignment: .bottom) {
            photo
            bottomScrim
            metadata
        }
        .background(Color.gradient(for: post.product.grad))
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThemeRadius.xl).stroke(Color.white.opacity(0.12)))
        .shadow(color: ThemeElevation.floating.color, radius: ThemeElevation.floating.radius, y: ThemeElevation.floating.y)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(post.product.name), \(photos.count) photos")
    }

    private var photo: some View {
        ZStack {
            Color.gradient(for: post.product.grad)
            if let currentPhoto = photos[safe: photoIndex] {
                CachedAsyncImage(url: currentPhoto, width: 900, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProductArtworkView(post: post)
            }
            VStack(spacing: 0) {
                photoProgress
                HStack(spacing: 0) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { previousPhoto() }
                    Color.clear.contentShape(Rectangle()).onTapGesture { nextPhoto() }
                }
            }
        }
        .accessibilityAdjustableAction { direction in
            direction == .increment ? nextPhoto() : previousPhoto()
        }
    }

    private var bottomScrim: some View {
        LinearGradient(
            colors: [.clear, Color.ink.opacity(0.18), Color.ink.opacity(0.88)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: requestsReliability ? 250 : 210)
        .allowsHitTesting(false)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: ThemeSpacing.xxs) {
                    Text(post.product.name)
                        .font(.title2.weight(.heavy))
                        .fontDesign(.rounded)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Text(post.product.brand)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.76))
                }
                Spacer(minLength: ThemeSpacing.sm)
                if post.product.price > 0 {
                    Text("$\(Int(post.product.price))")
                        .font(.title3.weight(.heavy))
                        .fixedSize()
                }
            }
            if requestsReliability {
                reliabilityPoll
            } else {
                Button(action: onDetails) {
                    Label("Swipe up for details", systemImage: "arrow.up")
                }
                .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .frame(minHeight: 44, alignment: .leading)
                    .accessibilityLabel("Product details")
            }
        }
        .padding(ThemeSpacing.md)
        .foregroundStyle(Color.white)
        .shadow(color: Color.ink.opacity(0.35), radius: 2, y: 1)
    }

    private var reliabilityPoll: some View {
        VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
            Text("Is this gift reliable?")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.white.opacity(0.9))
            HStack(spacing: ThemeSpacing.xs) {
                ForEach(ProductReliabilityVote.allCases, id: \.self) { vote in
                    Button { onReliabilityVote(vote) } label: {
                        Label(vote.title, systemImage: vote.symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.ink.opacity(0.38), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Adds a quality label after your swipe training")
                }
            }
        }
    }

    private var photoProgress: some View {
        HStack(spacing: ThemeSpacing.xxs) {
            ForEach(0..<max(photos.count, 1), id: \.self) { index in
                Capsule().fill(index == photoIndex ? Color.white : Color.white.opacity(0.35)).frame(height: 3)
            }
        }
        .padding(.horizontal, ThemeSpacing.sm)
        .padding(.horizontal, ThemeSpacing.xxs)
        .padding(.top, ThemeSpacing.xs)
        .shadow(color: Color.ink.opacity(0.45), radius: 2, y: 1)
    }

    private func previousPhoto() { photoIndex = max(0, photoIndex - 1) }
    private func nextPhoto() { photoIndex = min(max(photos.count - 1, 0), photoIndex + 1) }
}

private struct SwipeProductDetails: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TabView {
                        ForEach(post.product.gallery, id: \.self) { image in
                            CachedAsyncImage(url: image, width: 900, contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.cream)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .frame(height: 430)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(post.product.name).font(.largeTitle.weight(.heavy)).fontDesign(.rounded)
                        HStack {
                            Text(post.product.brand).foregroundStyle(.secondary)
                            Spacer()
                            if post.product.price > 0 { Text("$\(Int(post.product.price))").font(.title2.weight(.bold)).foregroundStyle(Color.coral) }
                        }
                        detailBlock("Why it fits", post.reason ?? post.caption)
                        if let story = post.story, !story.isEmpty, story != post.reason {
                            detailBlock("The details", story)
                        }
                        if let features = post.productFeatures, !features.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Product features").font(.headline)
                                ForEach(features, id: \.self) { feature in
                                    Label(feature.capitalized, systemImage: "checkmark.circle.fill")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Label("Your likes and passes update your private taste profile. Friends can use that profile when choosing a gift for you.", systemImage: "person.2.fill")
                            .font(.footnote).foregroundStyle(.secondary)
                            .padding().background(Color.coralSoft, in: RoundedRectangle(cornerRadius: 16))
                        if let value = post.productUrl, let url = URL(string: value) {
                            Button {
                                OutboundRouter.open(url, postId: post.id, source: "swipe_product") {
                                    UIApplication.shared.open($0)
                                }
                            } label: {
                                Label("Shop at \(post.domain ?? post.product.brand)", systemImage: "bag.fill")
                                    .font(.headline).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                                    .background(Color.coral, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 28)
                }
            }
            .background(Color.surface)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private func detailBlock(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(value.isEmpty ? "A curated, shoppable match from the reviewed catalog." : value)
                .font(.body).foregroundStyle(.secondary)
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
