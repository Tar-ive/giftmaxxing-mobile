import SwiftUI
import SwiftData

@MainActor
final class SwipeViewModel: ObservableObject {
    @Published var cards: [Post] = []
    @Published var currentIndex = 0
    @Published var isLoading = false
    @Published var yesCount = 0
    @Published var noCount = 0
    @Published var offset: CGSize = .zero
    @Published var isSwiping = false

    private let api = APIClient.shared
    private let analytics = AnalyticsEngine.shared

    // Tinder-style: track drag start time for hesitation detection
    private(set) var dragStartTime: Date?
    private var dragStartTranslation: CGSize = .zero
    // When the current card appeared — decision time (shown -> committed swipe)
    // scales the taste weight: an instant no is a harder no than a hesitant one.
    private var cardShownAt = Date()
    var userId: String?

    var currentCard: Post? {
        guard currentIndex < cards.count else { return nil }
        return cards[currentIndex]
    }

    var isFinished: Bool {
        currentIndex >= cards.count && !cards.isEmpty
    }

    func loadCards() async {
        guard !isLoading else { return }
        isLoading = true

        do {
            // Carry the consult's cold-start signals (who they gift for, world
            // vibes) so the deck leans the right way before any swipes exist.
            let vibes = PersonalizationStore.consultVibes
            let page = try await api.fetchRecommendations(
                limit: 50,
                vibes: vibes.isEmpty ? nil : vibes,
                recipient: PersonalizationStore.feedRecipient,
                userId: userId
            )
            let profile = await TasteProfileStore.shared.snapshot()
            cards = OnDeviceRanker.rank(
                candidates: page.posts,
                profile: profile,
                context: RankingContext(
                    recipient: PersonalizationStore.feedRecipient,
                    consultVibes: vibes,
                    mindset: GiftMindset.current()
                )
            ).prefix(30).map(\.post)
            currentIndex = 0
            yesCount = 0
            noCount = 0
            cardShownAt = Date()
            prefetchNextImages()

            if let first = cards.first {
                analytics.trackCardShown(
                    postId: first.id,
                    position: 0,
                    totalCards: cards.count
                )
            }
        } catch {
            // use empty state
        }

        isLoading = false
    }

    // "Surprise me" — the controlled walk AWAY from the taste cluster: fetch a
    // wide candidate page, measure each item's similarity to the taste
    // centroid, then deliberately deal from the LOW-similarity band
    // (quality-gated, category-diverse). Broadens horizons on purpose.
    func loadSurprise() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let page = try? await api.fetchFeed(
            limit: 60,
            cacheBuster: String(Int(Date().timeIntervalSince1970 * 1000))
        ) else { return }

        // Similarities to the taste centroid, from device-cached vectors.
        var similarities: [String: Float] = [:]
        let profile = await TasteProfileStore.shared.snapshot()
        if profile.seedKeys.count >= 3 {
            let missing = await VectorStore.shared.missingKeys(from: profile.seedKeys + page.posts.map(\.id))
            if !missing.isEmpty, let response = try? await api.fetchVectors(keys: missing) {
                for item in response.items ?? [] {
                    await VectorStore.shared.upsert(key: item.key, base64: item.data, scale: item.scale)
                }
            }
            if let centroid = await VectorStore.shared.centroid(of: profile.seedKeys) {
                similarities = await VectorStore.shared.similarities(keys: page.posts.map(\.id), to: centroid)
            }
        }

        cards = GiftGraphRanker.surpriseWalk(page.posts, centroidSimilarities: similarities, count: 14)
        currentIndex = 0
        yesCount = 0
        noCount = 0
        offset = .zero
        cardShownAt = Date()
        prefetchNextImages()
        AnalyticsEngine.shared.trackScreenView(screen: "swipe_surprise")
    }

    func onDragStart() {
        dragStartTime = Date()
        dragStartTranslation = offset
    }

    func onDragEnd(translation: CGSize, velocity: CGSize, context: ModelContext? = nil) {
        if translation.width > 100 {
            swipeRight(velocity: Double(velocity.width), context: context)
        } else if translation.width < -100 {
            swipeLeft(velocity: Double(velocity.width), context: context)
        } else {
            // Hesitation: user dragged but released without committing
            if let card = currentCard, let start = dragStartTime {
                let dragDistance = sqrt(
                    pow(Double(translation.width), 2) + pow(Double(translation.height), 2)
                )
                let dragDuration = Date().timeIntervalSince(start) * 1000
                if dragDistance > 30 {
                    analytics.trackSwipeHesitation(
                        postId: card.id,
                        dragDistance: dragDistance,
                        dragDurationMs: dragDuration
                    )
                }
            }
            withAnimation(.spring(response: 0.3)) {
                offset = .zero
            }
        }
        dragStartTime = nil
    }

    func swipeRight(velocity: Double = 500, context: ModelContext? = nil) {
        guard !isSwiping, currentIndex < cards.count else { return }
        isSwiping = true
        yesCount += 1
        let card = cards[currentIndex]
        SwipeListStore.shared.addToMyGiftIdeas(card)
        // Taste profile + batched upload (one Lambda invocation per ~10 swipes).
        record(.like, for: card, uploadAs: "like", decisionMs: decisionMs())

        analytics.trackSwipeRight(
            postId: card.id,
            velocity: abs(velocity),
            position: currentIndex
        )

        withAnimation(.spring(response: 0.4)) {
            offset = CGSize(width: 500, height: 0)
        }
        advanceAfterDelay()
    }

    func swipeLeft(velocity: Double = 500, context: ModelContext? = nil) {
        guard !isSwiping, currentIndex < cards.count else { return }
        isSwiping = true
        noCount += 1
        let card = cards[currentIndex]
        // Left-swipes are the strongest explicit negative signal the app has —
        // they feed both the on-device anti-centroid and server de-dup so a
        // passed gift never comes back on another session or device.
        record(.hide, for: card, uploadAs: "hide", decisionMs: decisionMs())

        analytics.trackSwipeLeft(
            postId: card.id,
            velocity: abs(velocity),
            position: currentIndex
        )

        withAnimation(.spring(response: 0.4)) {
            offset = CGSize(width: -500, height: 0)
        }
        advanceAfterDelay()
    }

    private func decisionMs() -> Double {
        Date().timeIntervalSince(cardShownAt) * 1000
    }

    private func record(_ kind: TasteEvent.Kind, for card: Post, uploadAs type: String?, decisionMs: Double = 0) {
        Task {
            let signals = TasteSignals.extract(from: card)
            // Snap decisions carry more conviction than long deliberations:
            // <1.2s scales the weight up (max 1.3×), >6s scales it down a bit.
            let scale: Double = decisionMs <= 0 ? 1 : decisionMs < 1200 ? 1.3 : decisionMs > 6000 ? 0.85 : 1
            await TasteProfileStore.shared.record(TasteEvent(
                kind: kind,
                postId: card.id,
                author: card.user,
                price: card.product.price,
                vibes: signals.vibes,
                category: signals.category,
                giftType: card.giftType ?? "product",
                weightScale: scale
            ))
            if let type {
                var data: [String: String] = ["giftType": card.giftType ?? "product"]
                if decisionMs > 0 { data["decisionMs"] = String(Int(decisionMs)) }
                await InteractionQueue.shared.enqueue(userId: userId, targetId: card.id, type: type, data: data)
            }
        }
    }

    private func advanceAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.currentIndex += 1
            self.offset = .zero
            self.isSwiping = false
            self.cardShownAt = Date()
            self.prefetchNextImages()

            // Track next card shown (Tinder tracks every card impression)
            if let next = self.currentCard {
                self.analytics.trackCardShown(
                    postId: next.id,
                    position: self.currentIndex,
                    totalCards: self.cards.count
                )
            } else if self.isFinished {
                self.analytics.trackDeckComplete(
                    yesCount: self.yesCount,
                    noCount: self.noCount,
                    totalCards: self.cards.count
                )
            }
        }
    }

    private func prefetchNextImages() {
        let start = currentIndex
        let end = min(cards.count, start + 5)
        guard start < end else { return }
        let urls = cards[start..<end].compactMap { $0.product.image }
        Task { await ImageLoader.shared.prefetch(urls: urls, width: 600) }
    }
}

struct SwipeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @StateObject private var viewModel = SwipeViewModel()
    @Environment(\.modelContext) private var modelContext

    // One swiping mechanic, two directions:
    //   • You     — self-gifting. Your own swipes train the taste model that
    //               powers every recommendation in the app.
    //   • People  — the challenge hub: everyone you gift for, their swipe
    //               results when they've answered, a share/nudge when they
    //               haven't (PeopleHubView). Gift Boards live on the You tab.
    private enum GiftContext: String, CaseIterable {
        case me = "You"
        case people = "People"
    }
    @State private var context: GiftContext = .me

    // First-deck gesture rehearsal — cleared by the first real swipe commit.
    @State private var showRehearsal = !SwipeRehearsal.seen

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                contextPicker

                // Swipe lists friends sent you, waiting to be answered.
                ChallengeInviteRail()

                if context == .people {
                    PeopleHubView()
                } else {
                    // The rehearsal cue overlays the DECK only. Sitting on the
                    // whole VStack, its repeating keyframe animation swallowed
                    // taps on the segment picker above it.
                    deckBody
                        .overlay {
                            if showRehearsal, viewModel.currentCard != nil, !viewModel.isLoading {
                                SwipeRehearsalCue()
                            }
                        }
                }
            }
            .background(Color.cream)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Swipe")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // The deliberate detour: deal a deck from OUTSIDE the
                    // predicted taste cluster.
                    if context == .me {
                        Button {
                            Task { await viewModel.loadSurprise() }
                        } label: {
                            Image(systemName: "dice.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.coral)
                        }
                        .accessibilityLabel("Surprise me — ideas outside your usual taste")
                    }
                }
            }
        }
        .onChange(of: viewModel.yesCount + viewModel.noCount) { _, total in
            // First real commit = rehearsal complete, forever.
            if total > 0, showRehearsal {
                SwipeRehearsal.seen = true
                withAnimation(.easeOut(duration: 0.3)) { showRehearsal = false }
            }
        }
        .onChange(of: context) { _, newContext in
            switch newContext {
            case .me:
                Task { await viewModel.loadCards() }
            case .people:
                AnalyticsEngine.shared.trackScreenView(screen: "swipe_people")
            }
        }
        .task {
            viewModel.userId = authManager.userId
            if viewModel.cards.isEmpty {
                AnalyticsEngine.shared.trackScreenView(screen: "swipe")
                await viewModel.loadCards()
            }
        }
        .onAppear { appState.suppressMaxiFAB() }
        .onDisappear { appState.unsuppressMaxiFAB() }
    }

    // Context picker — who is this swiping session for?
    private var contextPicker: some View {
        HStack(spacing: 0) {
            ForEach(GiftContext.allCases, id: \.self) { ctx in
                Button {
                    context = ctx
                } label: {
                    Text(ctx.rawValue)
                        .font(.system(size: 16, weight: context == ctx ? .semibold : .regular))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            context == ctx ? Color.surface : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityAddTraits(context == ctx ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.ink.opacity(0.08), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Swipe context")
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var deckBody: some View {
        Group {
                if viewModel.isLoading {
                    Spacer()
                    ProgressView("Loading gifts...")
                        .font(.bodyMedium)
                    Spacer()
                } else if viewModel.isFinished {
                    SwipeCompleteView(
                        yesCount: viewModel.yesCount,
                        noCount: viewModel.noCount,
                        onRestart: {
                            Task { await viewModel.loadCards() }
                        }
                    )
                } else if let card = viewModel.currentCard {
                    // Progress
                    HStack(spacing: 4) {
                        Text("\(viewModel.currentIndex + 1)/\(viewModel.cards.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 8) {
                            Label("\(viewModel.yesCount)", systemImage: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(Color.coral)
                            Label("\(viewModel.noCount)", systemImage: "xmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Card — explicit width from the measured screen so a
                    // fill-mode image can never inflate the layout past the
                    // device edge (reported on 390pt-wide phones).
                    GeometryReader { geo in
                        SwipeCardView(
                            post: card,
                            cardWidth: min(geo.size.width - 40, 500)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(viewModel.offset)
                        .rotationEffect(.degrees(Double(viewModel.offset.width) / 20))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if viewModel.dragStartTime == nil {
                                        viewModel.onDragStart()
                                    }
                                    viewModel.offset = value.translation
                                }
                                .onEnded { value in
                                    viewModel.onDragEnd(
                                        translation: value.translation,
                                        velocity: value.velocity,
                                        context: modelContext
                                    )
                                }
                        )
                    }

                    // Action buttons
                    HStack(spacing: 40) {
                        Button(action: { viewModel.swipeLeft(context: modelContext) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.red)
                                .frame(width: 64, height: 64)
                                .background(Color.surface)
                                .clipShape(Circle())
                                .shadow(color: .red.opacity(0.2), radius: 8)
                        }
                        .disabled(viewModel.isSwiping)

                        Button(action: { viewModel.swipeRight(context: modelContext) }) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color.coral)
                                .frame(width: 64, height: 64)
                                .background(Color.surface)
                                .clipShape(Circle())
                                .shadow(color: Color.coral.opacity(0.3), radius: 8)
                        }
                        .disabled(viewModel.isSwiping)
                    }
                    .padding(.bottom, 24)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "rectangle.portrait.on.rectangle.portrait.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No gifts to swipe")
                            .font(.displaySmall)
                        Button("Load gifts") {
                            Task { await viewModel.loadCards() }
                        }
                        .font(.labelBold)
                        .foregroundStyle(Color.coral)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
        }
    }
}

struct SwipeCardView: View {
    let post: Post
    var cardWidth: CGFloat = UIScreen.main.bounds.width - 40

    // The card takes the SHAPE OF THE PHOTO (Tinder-style) instead of a fixed
    // box that letterboxed tall images and cropped wide ones. Measured from
    // the decoded image; clamped so the info row + buttons always fit.
    @State private var measuredAspect: CGFloat?

    private var imageHeight: CGFloat {
        let short = UIScreen.main.bounds.height < 700
        let minHeight: CGFloat = short ? 220 : 260
        let maxHeight: CGFloat = UIScreen.main.bounds.height * (short ? 0.46 : 0.54)
        guard let aspect = measuredAspect, aspect > 0 else {
            return short ? 260 : 340
        }
        return min(max(cardWidth / aspect, minHeight), maxHeight)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Product image. Fixed frame + clipped: a fill-mode image reports
            // a width wider than proposed when its aspect demands it, which
            // was inflating the card past the screen edge. An EXPLICIT width
            // (not maxWidth) makes overflow impossible.
            ZStack {
                // Photo when we have one; the designed brand lockup when we
                // don't (catalog items pre-enrichment, services).
                if let image = post.product.image {
                    Color.gradient(for: post.product.grad)
                    CachedAsyncImage(url: image, width: 600) { ratio in
                        if measuredAspect == nil {
                            withAnimation(.snappy) { measuredAspect = ratio }
                        }
                    }
                    .frame(width: cardWidth, height: imageHeight)
                    .clipped()
                } else {
                    ProductArtworkView(post: post)
                }

                // Service cards (a year of Spotify, a Costco membership) swipe
                // exactly like products — the badge is the only tell, and the
                // yes/no lands in the product-vs-service taste split.
                if post.isService {
                    VStack {
                        HStack {
                            ServiceBadge(duration: post.serviceDuration)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(12)
                }
            }
            .frame(width: cardWidth, height: imageHeight)
            .clipped()
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))

            // Info
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(post.product.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text("$\(Int(post.product.price))")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.coral)
                        .fixedSize()
                }

                Text(post.product.brand)
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)

                if !post.caption.isEmpty {
                    Text(post.caption)
                        .font(.bodyMedium)
                        .foregroundStyle(Color.ink)
                        .lineLimit(3)
                }

                if let reason = post.reason {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                        Text(reason)
                            .font(.caption)
                    }
                    .foregroundStyle(Color.coral)
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .frame(width: cardWidth, alignment: .leading)
            .background(Color.surface)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        }
        .frame(width: cardWidth)
        .shadow(color: .black.opacity(0.1), radius: 16, y: 8)
    }
}

struct SwipeCompleteView: View {
    let yesCount: Int
    let noCount: Int
    var onRestart: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(Color.coral)

            Text("All done!")
                .font(.displayLarge)
                .foregroundStyle(Color.ink)

            Text("You liked \(yesCount) gifts out of \(yesCount + noCount)")
                .font(.bodyLarge)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("\(yesCount)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.coral)
                    Text("Liked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Text("\(noCount)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("Passed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 20)

            Button(action: { onRestart?() }) {
                Text("Swipe again")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 40)

            // Post-task conversion moment (mirrors the web reveal): you just
            // learned YOUR taste — now capture a friend's.
            NavigationLink(destination: ChallengeView()) {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14))
                    Text("Challenge a friend to swipe")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(Color.coral)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.coral.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }
}
