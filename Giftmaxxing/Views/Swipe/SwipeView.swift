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

    var currentCard: Post? {
        guard currentIndex < cards.count else { return nil }
        return cards[currentIndex]
    }

    var isFinished: Bool {
        currentIndex >= cards.count && !cards.isEmpty
    }

    // "My list" deck — the posts you queued from the feed for a friend.
    // Swiping left prunes the item off the list before you send it.
    var isMyListMode = false

    func loadMyList() {
        isMyListMode = true
        cards = SwipeListStore.shared.posts
        currentIndex = 0
        yesCount = 0
        noCount = 0
        offset = .zero
        cardShownAt = Date()
        prefetchNextImages()
    }

    func loadCards() async {
        guard !isLoading else { return }
        isMyListMode = false
        isLoading = true

        do {
            // Carry the consult's cold-start signals (who they gift for, world
            // vibes) so the deck leans the right way before any swipes exist.
            let vibes = PersonalizationStore.consultVibes
            let page = try await api.fetchRecommendations(
                limit: 30,
                vibes: vibes.isEmpty ? nil : vibes,
                recipient: PersonalizationStore.feedRecipient
            )
            cards = page.posts
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
        // they feed the on-device taste profile (and de-dup) but stay local.
        record(.hide, for: card, uploadAs: nil, decisionMs: decisionMs())
        if isMyListMode {
            SwipeListStore.shared.remove(id: card.id)
        }

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
                await InteractionQueue.shared.enqueue(userId: nil, targetId: card.id, type: type, data: data)
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
    @StateObject private var viewModel = SwipeViewModel()
    @ObservedObject private var swipeList = SwipeListStore.shared
    @Environment(\.modelContext) private var modelContext

    // One swiping mechanic, three gifting contexts:
    //   • For me      — self-gifting: train your taste, find your own things.
    //   • For someone — one recipient: send THEM a swipe challenge to learn
    //                   their taste, or curate a deck from your list.
    //   • Group gift  — lives in the Circles tab; picking the segment jumps
    //                   there (embedding it here left a dead-end segment).
    private enum GiftContext: String, CaseIterable {
        case me = "For me"
        case someone = "For someone"
        case group = "Group gift"
    }
    @State private var context: GiftContext = .me

    private enum DeckMode {
        case forYou
        case myList
    }
    @State private var mode: DeckMode = .forYou

    // Swipe-list sharing: the list becomes a server-side challenge seeded with
    // its items, and the friend gets a swipeable browser link — not a text blob.
    @State private var listInviteURL: URL?
    @State private var buildingListLink = false
    // Which exact set of items the cached link was built for — the link goes
    // stale the moment the list's contents change, not just its count.
    @State private var listLinkKey = ""

    private var currentListKey: String {
        swipeList.posts.map(\.id).joined(separator: "|")
    }

    private var senderId: String {
        appState.currentUser?.id ?? InteractionQueue.anonymousUserId
    }

    @MainActor
    private func buildListInviteLink() async {
        let posts = swipeList.posts
        guard !posts.isEmpty, !buildingListLink else { return }
        buildingListLink = true
        defer { buildingListLink = false }
        let inviterName = appState.currentUser?.name ?? "A friend"
        var challengeId: String?
        if let response = try? await APIClient.shared.createChallenge(
            senderId: senderId,
            seedKeys: posts.map(\.id),
            inviterName: inviterName
        ) {
            challengeId = response.challengeId
        }
        // Even if the server deck fails, the legacy local-deck link still works.
        listInviteURL = InviteLink.buildURL(
            inviterName: inviterName,
            senderId: senderId,
            challengeId: challengeId
        )
        listLinkKey = posts.map(\.id).joined(separator: "|")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Context picker — who is this swiping session for?
                Picker("Context", selection: $context) {
                    ForEach(GiftContext.allCases, id: \.self) { ctx in
                        Text(ctx.rawValue).tag(ctx)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 6)

                if context == .someone {
                    // The single-recipient toolkit: learn their taste via a
                    // challenge, or hand-pick a deck from your saved list.
                    if !swipeList.posts.isEmpty {
                        sendListCard
                    }

                    NavigationLink(destination: ChallengeView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.coral)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Find their taste — send a swipe challenge")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.ink)
                                Text("They swipe in their browser; their gift taste lands here.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Color.coralSoft.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    deckBody
                } else {
                    deckBody
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
                    if context == .someone {
                        // Send the curated deck — the whole point of the list.
                        if let url = listInviteURL, listLinkKey == currentListKey {
                            ShareLink(item: url, message: Text(InviteLink.shareText)) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.coral)
                            }
                        } else {
                            Button {
                                Task { await buildListInviteLink() }
                            } label: {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(swipeList.posts.isEmpty ? Color.secondary : Color.coral)
                            }
                            .disabled(swipeList.posts.isEmpty || buildingListLink)
                        }
                    } else if context == .me {
                        NavigationLink(destination: ChallengeView()) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.coral)
                        }
                    }
                }
            }
        }
        .onChange(of: context) { _, newContext in
            switch newContext {
            case .me:
                mode = .forYou
                Task { await viewModel.loadCards() }
            case .someone:
                mode = .myList
                viewModel.loadMyList()
            case .group:
                // Group gifting lives in Circles — hand off and reset the
                // segment so Swipe isn't stuck on a blank context.
                appState.selectedTab = .circles
                context = .me
            }
        }
        .task {
            if viewModel.cards.isEmpty {
                AnalyticsEngine.shared.trackScreenView(screen: "swipe")
                await viewModel.loadCards()
            }
        }
    }

    // The "how do I GIVE this list?" answer, rendered right above the deck:
    // one tap turns the list into a swipe link the friend opens in a browser.
    @ViewBuilder
    private var sendListCard: some View {
        Group {
            if let url = listInviteURL, listLinkKey == currentListKey {
                ShareLink(item: url, message: Text(InviteLink.shareText)) {
                    sendListLabel(
                        title: "Send the swipe link",
                        subtitle: "They swipe your \(swipeList.posts.count) picks in their browser — no app needed.",
                        icon: "paperplane.fill"
                    )
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task { await buildListInviteLink() }
                } label: {
                    sendListLabel(
                        title: buildingListLink ? "Building their deck…" : "Send this list to a friend",
                        subtitle: "Turns your \(swipeList.posts.count) picks into a swipeable link.",
                        icon: "link"
                    )
                }
                .buttonStyle(.plain)
                .disabled(buildingListLink)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private func sendListLabel(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            if buildingListLink {
                ProgressView()
                    .frame(width: 24)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(12)
        .background(Color.coral)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var deckBody: some View {
        Group {
                if mode == .myList && swipeList.posts.isEmpty && viewModel.cards.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Your swipe list is empty")
                            .font(.displaySmall)
                        Text("See something in the feed a friend might love?\nTap “Add to swipe list”, then send them the deck.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(.horizontal, 30)
                } else if viewModel.isLoading {
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

    // Adapt to small devices (SE = 667pt tall) so the card + buttons always fit.
    private var imageHeight: CGFloat {
        UIScreen.main.bounds.height < 700 ? 260 : 340
    }

    var body: some View {
        VStack(spacing: 0) {
            // Product image. Fixed frame + clipped: a fill-mode image reports
            // a width wider than proposed when its aspect demands it, which
            // was inflating the card past the screen edge. An EXPLICIT width
            // (not maxWidth) makes overflow impossible.
            ZStack {
                Color.gradient(for: post.product.grad)

                Text(post.product.emoji)
                    .font(.system(size: 72))

                if let image = post.product.image {
                    CachedAsyncImage(url: image, width: 600)
                        .frame(width: cardWidth, height: imageHeight)
                        .clipped()
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
