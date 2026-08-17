import SwiftUI
import GiftmaxxingCore
import GiftmaxxingRecommendation
import GiftmaxxingNetworking
import GiftmaxxingDesignSystem

// Onboarding taste calibration — the deck that teaches the app who you are.
//
// WHY THIS EXISTS
// Swiping was something a user might stumble into, so most accounts produced
// ZERO preference labels. Measured across the whole product: 70 positive swipe
// labels from 19 people, which is far too few to tell a learned ranker apart
// from plain cosine similarity (the confidence interval on that comparison is
// ±0.15 — wider than any effect we could hope to see).
//
// Every new account that swipes this deck contributes ~12 labels on day one.
// That is the only lever that closes the gap; no model change can.
//
// It also pays for itself immediately for the USER: the feed is personalised
// from first launch instead of showing generic top-of-catalog until they
// happen to interact with something.
//
// Swipes flow through the SAME TasteProfileStore + InteractionQueue path as
// the Swipe tab, so these are real signals and real training labels — not a
// throwaway onboarding animation.
struct TasteCalibrationStep: View {
    /// Fires once the minimum is reached so the parent can enable "Continue".
    var onProgress: (Int) -> Void

    static let minimumSwipes = 5

    @State private var cards: [Post] = []
    @State private var index = 0
    @State private var offset: CGSize = .zero
    @State private var isLoading = true
    @State private var failed = false
    @State private var swipeCount = 0
    @State private var likeCount = 0
    @State private var cardShownAt = Date()
    @State private var feedback = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var current: Post? { cards.indices.contains(index) ? cards[index] : nil }
    private var done: Bool { swipeCount >= Self.minimumSwipes }

    var body: some View {
        VStack(spacing: ThemeSpacing.md) {
            header

            ZStack {
                if isLoading {
                    RoundedRectangle(cornerRadius: ThemeRadius.xl, style: .continuous)
                        .fill(Color.surfaceSunken)
                        .frame(height: 380)
                        .overlay(ProgressView())
                } else if failed || cards.isEmpty {
                    emptyState
                } else if let card = current {
                    // One card behind, for depth — the next thing to judge.
                    if cards.indices.contains(index + 1) {
                        cardView(cards[index + 1])
                            .scaleEffect(0.94)
                            .offset(y: 14)
                            .opacity(0.55)
                    }
                    cardView(card)
                        .offset(offset)
                        .rotationEffect(.degrees(Double(offset.width / 22)))
                        .gesture(dragGesture)
                        .overlay(alignment: offset.width > 0 ? .topLeading : .topTrailing) {
                            if abs(offset.width) > 40 { verdictBadge }
                        }
                } else {
                    finishedState
                }
            }
            .frame(height: 380)
            .animation(reduceMotion ? .none : .snappy, value: index)

            if current != nil { buttons }

            progress
        }
        .task { await load() }
        .sensoryFeedback(.impact(weight: .medium), trigger: feedback)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 6) {
            Text("Which of these would you gift?")
                .font(.title2.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
            Text("Swipe right for yes, left for no.")
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
        }
    }

    private func cardView(_ post: Post) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.gradient(for: post.product.grad)
            if let image = post.product.image {
                CachedAsyncImage(url: image, width: 800)
            }
            LinearGradient(colors: [.clear, Color.black.opacity(0.65)],
                           startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(post.product.name)
                    .font(.headline)
                    .foregroundStyle(Color.onPrimary)
                    .lineLimit(2)
                if post.product.price > 0 {
                    Text(post.product.price, format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.onPrimary.opacity(0.9))
                }
            }
            .padding(ThemeSpacing.md)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.xl, style: .continuous))
        .shadow(color: ThemeElevation.floating.color,
                radius: ThemeElevation.floating.radius, y: ThemeElevation.floating.y)
    }

    private var verdictBadge: some View {
        Text(offset.width > 0 ? "YES" : "NO")
            .font(.title2.weight(.heavy))
            .foregroundStyle(offset.width > 0 ? Color.success : Color.danger)
            .padding(.horizontal, ThemeSpacing.sm)
            .padding(.vertical, 6)
            .background(Color.surface.opacity(0.92), in: Capsule())
            .padding(ThemeSpacing.md)
    }

    private var buttons: some View {
        HStack(spacing: ThemeSpacing.xl) {
            Button { swipe(liked: false) } label: {
                Image(systemName: "xmark")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.danger)
                    .frame(width: 58, height: 58)
                    .background(Color.surface, in: Circle())
                    .shadow(color: ThemeElevation.card.color, radius: ThemeElevation.card.radius, y: 3)
            }
            .accessibilityLabel("Not for me")

            Button { swipe(liked: true) } label: {
                Image(systemName: "heart.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.onPrimary)
                    .frame(width: 58, height: 58)
                    .background(Color.coral, in: Circle())
                    .shadow(color: Color.coral.opacity(0.35), radius: 12, y: 4)
            }
            .accessibilityLabel("I'd gift this")
        }
        .buttonStyle(.plain)
    }

    private var progress: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(0..<Self.minimumSwipes, id: \.self) { i in
                    Capsule()
                        .fill(i < swipeCount ? Color.coral : Color.line)
                        .frame(height: 4)
                }
            }
            Text(done
                 ? "Nice — that's enough to start."
                 : "\(Self.minimumSwipes - swipeCount) more to personalise your feed")
                .font(.footnote)
                .foregroundStyle(done ? Color.success : Color.inkTertiary)
                .contentTransition(.opacity)
        }
        .animation(.snappy, value: swipeCount)
    }

    private var emptyState: some View {
        VStack(spacing: ThemeSpacing.sm) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(Color.inkTertiary)
            Text("Couldn't load ideas right now.")
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
            Button("Try again") { Task { await load() } }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var finishedState: some View {
        VStack(spacing: ThemeSpacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.success)
            Text("That's the deck — \(likeCount) saved.")
                .font(.headline)
                .foregroundStyle(Color.ink)
        }
    }

    // MARK: - Behaviour

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { offset = $0.translation }
            .onEnded { value in
                if abs(value.translation.width) > 110 {
                    swipe(liked: value.translation.width > 0)
                } else {
                    withAnimation(.snappy) { offset = .zero }
                }
            }
    }

    private func swipe(liked: Bool) {
        guard let card = current else { return }
        let decisionMs = Date().timeIntervalSince(cardShownAt) * 1000
        feedback += 1
        swipeCount += 1
        if liked { likeCount += 1 }

        // Same path the Swipe tab uses — on-device taste profile plus a
        // server-side interaction row. These become training labels.
        Task {
            let signals = TasteSignals.extract(from: card)
            let scale: Double = decisionMs < 1200 ? 1.3 : decisionMs > 6000 ? 0.85 : 1
            await TasteProfileStore.shared.record(TasteEvent(
                kind: liked ? .like : .hide,
                postId: card.id,
                author: card.user,
                price: card.product.price,
                vibes: signals.vibes,
                category: signals.category,
                giftType: card.giftType ?? "product",
                weightScale: scale
            ))
            await InteractionQueue.shared.enqueue(
                userId: AuthManager.shared.userId ?? InteractionQueue.anonymousUserId,
                targetId: card.id,
                type: liked ? "like" : "hide",
                data: ["decisionMs": String(Int(decisionMs)), "source": "onboarding_calibration"]
            )
        }
        // Mirrors the Swipe tab's telemetry so these land in the same
        // swipe_right/swipe_left stream the exporter reads.
        if liked {
            AnalyticsEngine.shared.trackSwipeRight(postId: card.id, velocity: 0, position: index)
        } else {
            AnalyticsEngine.shared.trackSwipeLeft(postId: card.id, velocity: 0, position: index)
        }

        onProgress(swipeCount)
        withAnimation(reduceMotion ? .none : .snappy) {
            offset = CGSize(width: liked ? 600 : -600, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            index += 1
            offset = .zero
            cardShownAt = Date()
        }
    }

    // Card 1 should never be random. By this point onboarding has collected
    // four independent signals — persona, gift styles, who they shop for, and
    // their budget — and the deck used to throw three of them away. Seeding
    // from all four is the difference between "here is the catalog" and "here
    // is a guess at you", and a better first card produces a better label.
    private func load() async {
        isLoading = true
        failed = false

        let vibes = Array(Set(GiftingPrefs.giftStyles + PersonalizationStore.consultVibes))
        var page = try? await APIClient.shared.fetchFeed(
            limit: 40,
            vibes: vibes.isEmpty ? nil : vibes,
            recipient: Self.primaryRecipient(),
            budget: Self.budgetCeiling()
        )
        // Every one of those is a SOFT preference server-side, but a narrow
        // combination can still come back thin. Widen rather than show a
        // half-empty deck.
        if (page?.posts ?? []).count < 8 {
            page = try? await APIClient.shared.fetchFeed(
                limit: 40, vibes: vibes.isEmpty ? nil : vibes
            )
        }
        if (page?.posts ?? []).count < 8 {
            page = try? await APIClient.shared.fetchFeed(limit: 40)
        }

        // Only cards with a real photo — judging a placeholder teaches nothing.
        let usable = (page?.posts ?? []).filter { $0.product.image != nil }
        cards = Array(usable.prefix(14))
        failed = cards.isEmpty
        isLoading = false
        cardShownAt = Date()
    }

    /// The relationship they picked, mapped to the catalog's recipient
    /// vocabulary. A miss costs nothing — the server treats recipient as a
    /// soft boost, not a filter.
    static func primaryRecipient() -> String? {
        // Per-contact tags first: they describe who is ACTUALLY in the user's
        // calendar, whereas GiftingPrefs.relationships is an aggregate
        // self-report. "I put my sister in" beats "I generally buy for
        // siblings" — and the most imminent birthday is the one they came here
        // to solve.
        let perContact = [
            "Partner": "partner", "Mom": "mom", "Dad": "dad", "Sibling": "sister",
            "Friend": "friend", "Kid": "kids", "Grandparent": "grandma",
            "Coworker": "coworker",
        ]
        if let tagged = GiftingPrefs.contactRelationships.compactMap({ perContact[$0] }).first {
            return tagged
        }
        let selfReported = [
            "Partner": "partner", "Parent": "parents", "Best friend": "friend",
            "Sibling": "sister", "Grandparent": "grandma", "Coworker": "coworker",
            "My kids": "kids",
        ]
        return GiftingPrefs.relationships.compactMap { selfReported[$0] }.first
    }

    /// Upper bound of the budget band. "$200+" has no ceiling, so it returns
    /// nil rather than a made-up number.
    static func budgetCeiling() -> Double? {
        switch GiftingPrefs.budget {
        case "Under $25": return 25
        case "$25–75": return 75
        case "$75–200": return 200
        default: return nil
        }
    }
}
