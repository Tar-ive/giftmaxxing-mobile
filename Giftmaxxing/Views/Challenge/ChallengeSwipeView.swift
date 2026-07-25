import SwiftUI

// Native, in-app challenge swiping — no browser bounce. An invite arriving in
// a DM, a deep link (giftmaxxing://challenge/<id>), or a pasted invite URL
// opens THIS deck: the same GET /challenges/{id} → swipe → POST response flow
// the web guest page runs, but inside the app. The web link keeps working for
// friends without the app — this is the first-class path for those with it.
struct ChallengeRef: Identifiable {
    let id: String
}

struct ChallengeSwipeView: View {
    let challengeId: String

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var status: ChallengeStatusResponse?
    @State private var loadFailed = false
    @State private var index = 0
    @State private var offset: CGSize = .zero
    @State private var swipes: [(id: String, dir: String, dwellMs: Double)] = []
    // Telemetry: how long each card was actually looked at, and whether they
    // walked away mid-deck. A fast yes and a long deliberation are different
    // signals, and an abandoned deck is its own answer.
    @State private var cardShownAt = Date()
    @State private var maxIndexSeen = 0
    // Measured photo shape per card (adaptive card height).
    @State private var cardAspect: [String: CGFloat] = [:]
    @State private var submitted = false
    @State private var submitting = false

    private var deck: [ChallengeCreateResponse.ChallengeDeckItem] {
        status?.deck ?? []
    }

    private var currentCard: ChallengeCreateResponse.ChallengeDeckItem? {
        deck.indices.contains(index) ? deck[index] : nil
    }

    private var yesCount: Int { swipes.filter { $0.dir == "yes" }.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if status == nil && !loadFailed {
                    Spacer()
                    ProgressView("Opening their picks…")
                        .font(.bodyMedium)
                    Spacer()
                } else if loadFailed {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Couldn't load this challenge — try again in a moment.")
                            .font(.bodyMedium)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(30)
                    Spacer()
                } else if submitted {
                    completedView
                } else if let card = currentCard {
                    header
                    deckCard(card)
                    actionButtons
                } else {
                    // Deck finished — send the answers.
                    Spacer()
                    VStack(spacing: 14) {
                        Image(systemName: "paperplane.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.coral)
                        Text("That's all \(deck.count) — send your answers?")
                            .font(.displaySmall)
                            .foregroundStyle(Color.ink)
                        Button {
                            Task { await submit() }
                        } label: {
                            Text(submitting ? "Sending…" : "Send to \(status?.inviterName ?? "them")")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.coral)
                                .clipShape(Capsule())
                        }
                        .disabled(submitting)
                        .padding(.horizontal, 40)
                    }
                    Spacer()
                }
            }
            .background(Color.cream)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(status?.inviterName.map { "\($0)'s picks" } ?? "Gift challenge")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task { await load() }
            .onDisappear { trackExitIfIncomplete() }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            if let to = status?.to, !to.isEmpty {
                let occasionSuffix = (status?.occasion).map { " · \($0)" } ?? ""
                Text("Made for \(to)\(occasionSuffix)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.coral)
            }
            Text("Swipe right on what you'd love, left on what you wouldn't.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("\(min(index + 1, deck.count))/\(deck.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 10)
    }

    // Cards take the shape of their photo instead of a fixed 1.1 box, so a
    // tall product isn't cropped and a square one isn't padded out.
    private func imageHeight(for card: ChallengeCreateResponse.ChallengeDeckItem, width: CGFloat) -> CGFloat {
        let maxHeight = UIScreen.main.bounds.height * 0.58
        guard let aspect = cardAspect[card.postId], aspect > 0 else { return width * 1.1 }
        return min(max(width / aspect, width * 0.75), maxHeight)
    }

    private func deckCard(_ card: ChallengeCreateResponse.ChallengeDeckItem) -> some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 40, 500)
            VStack(spacing: 0) {
                ZStack {
                    Color.gradient(for: .coral)
                    if let image = card.image {
                        CachedAsyncImage(url: image, width: 600) { ratio in
                            if cardAspect[card.postId] == nil {
                                withAnimation(.snappy) { cardAspect[card.postId] = ratio }
                            }
                        }
                    }
                    if card.giftType == "service" {
                        VStack {
                            HStack {
                                ServiceBadge(duration: card.serviceDuration)
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding(12)
                    }
                }
                .frame(width: width, height: imageHeight(for: card, width: width))
                .clipped()
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))

                HStack(alignment: .firstTextBaseline) {
                    Text(card.name ?? "Gift idea")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if let price = card.price, price > 0 {
                        Text("$\(Int(price))")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.coral)
                            .fixedSize()
                    }
                }
                .padding(16)
                .frame(width: width, alignment: .leading)
                .background(Color.surface)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
            }
            .shadow(color: .black.opacity(0.1), radius: 16, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(offset)
            .rotationEffect(.degrees(Double(offset.width) / 20))
            .gesture(
                DragGesture()
                    .onChanged { offset = $0.translation }
                    .onEnded { value in
                        if value.translation.width > 100 {
                            swipe("yes")
                        } else if value.translation.width < -100 {
                            swipe("no")
                        } else {
                            withAnimation(.spring(response: 0.3)) { offset = .zero }
                        }
                    }
            )
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 40) {
            Button { swipe("no") } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.red)
                    .frame(width: 64, height: 64)
                    .background(Color.surface)
                    .clipShape(Circle())
                    .shadow(color: .red.opacity(0.2), radius: 8)
            }
            Button { swipe("yes") } label: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.coral)
                    .frame(width: 64, height: 64)
                    .background(Color.surface)
                    .clipShape(Circle())
                    .shadow(color: Color.coral.opacity(0.3), radius: 8)
            }
        }
        .padding(.bottom, 24)
    }

    private var completedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.coral)
            Text("Sent!")
                .font(.displayLarge)
                .foregroundStyle(Color.ink)
            Text("You loved \(yesCount) of \(swipes.count) — \(status?.inviterName ?? "they") can see your answers now.")
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Done") { dismiss() }
                .font(.labelBold)
                .foregroundStyle(Color.coral)
            Spacer()
        }
    }

    private func swipe(_ dir: String) {
        guard let card = currentCard else { return }
        let dwellMs = Date().timeIntervalSince(cardShownAt) * 1000
        swipes.append((id: card.postId, dir: dir, dwellMs: dwellMs))
        if dir == "yes" {
            AnalyticsEngine.shared.trackSwipeRight(postId: card.postId, velocity: 0, position: index)
        } else {
            AnalyticsEngine.shared.trackSwipeLeft(postId: card.postId, velocity: 0, position: index)
        }
        withAnimation(.spring(response: 0.35)) {
            offset = CGSize(width: dir == "yes" ? 500 : -500, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            index += 1
            maxIndexSeen = max(maxIndexSeen, index)
            cardShownAt = Date()
            offset = .zero
        }
    }

    // Left mid-deck: record what they got through so an abandoned list still
    // tells the sender something (and never looks like a finished response).
    private func trackExitIfIncomplete() {
        guard !submitted, !deck.isEmpty, swipes.count < deck.count else { return }
        AnalyticsEngine.shared.trackChallengeAbandoned(
            challengeId: challengeId,
            swiped: swipes.count,
            deckSize: deck.count,
            yesCount: yesCount
        )
    }

    private func load() async {
        do {
            status = try await APIClient.shared.fetchChallengeStatus(challengeId: challengeId)
            loadFailed = (status?.deck ?? []).isEmpty
            cardShownAt = Date()
        } catch {
            loadFailed = true
        }
    }

    private func submit() async {
        guard !submitting, !swipes.isEmpty else { return }
        submitting = true
        defer { submitting = false }
        let guestName = authManager.displayName ?? "A friend"
        do {
            try await APIClient.shared.submitChallengeResponse(
                challengeId: challengeId,
                guestName: guestName,
                swipes: swipes,
                anonId: InteractionQueue.anonymousUserId,
                viewerUserId: authManager.userId
            )
            submitted = true
            AnalyticsEngine.shared.trackDeckComplete(
                yesCount: yesCount,
                noCount: swipes.count - yesCount,
                totalCards: deck.count
            )
        } catch {
            // Leave the send button up — the guest can retry.
        }
    }
}

// Pick a friend and send them something over an in-app DM — the invite path
// that never leaves the app. Falls back gracefully: no accepted friends yet →
// nudge toward the share sheet instead.
struct FriendPickerSheet: View {
    /// Message posted into the DM thread (should include the invite URL so
    /// the recipient's thread renders the "swipe it here" card).
    let messageText: String
    var onSent: ((String) -> Void)? = nil

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = FriendsStore.shared
    @State private var busyFriendId: String?
    @State private var sentFriendId: String?

    private var accepted: [Friendship] {
        store.friends.filter(\.isAccepted)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    if accepted.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "person.2")
                                .font(.system(size: 30))
                                .foregroundStyle(.secondary)
                            Text("No in-app friends yet")
                                .font(.displaySmall)
                                .foregroundStyle(Color.ink)
                            Text("Add friends from Search → People, or use the share sheet to send the link anywhere.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(30)
                    }
                    ForEach(accepted) { friend in
                        Button {
                            Task { await send(to: friend) }
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(name: friend.name ?? friend.friendId, grad: .sky, size: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(friend.name ?? "Friend")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.ink)
                                    if let handle = friend.handle {
                                        Text("@\(handle)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if sentFriendId == friend.friendId {
                                    Label("Sent", systemImage: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(Color.coral)
                                } else if busyFriendId == friend.friendId {
                                    ProgressView()
                                } else {
                                    Image(systemName: "paperplane")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.coral)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .disabled(busyFriendId != nil || sentFriendId == friend.friendId)
                    }
                }
                .padding(.vertical, 12)
            }
            .background(Color.surface)
            .navigationTitle("Send in the app")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.coral)
                }
            }
            .task {
                if let userId = authManager.userId {
                    await store.refresh(userId: userId, query: "")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send(to friend: Friendship) async {
        guard let userId = authManager.userId else { return }
        busyFriendId = friend.friendId
        defer { busyFriendId = nil }
        guard let threadId = await store.openDm(userId: userId, otherUserId: friend.friendId) else { return }
        let name = authManager.displayName ?? "A friend"
        if await store.sendMessage(threadId: threadId, userId: userId, name: name, text: messageText) != nil {
            sentFriendId = friend.friendId
            onSent?(friend.friendId)
        }
    }
}
