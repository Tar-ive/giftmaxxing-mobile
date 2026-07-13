import SwiftUI

// The "For someone" home: every swipe list you keep, one per person/occasion
// (Instagram-collections model). Tap into a list to manage its items, send it
// as a swipe deck, and read the yes/no results back.
struct SwipeListsHomeView: View {
    @ObservedObject private var store = SwipeListStore.shared
    @State private var showNewList = false
    @State private var newListName = ""
    @State private var newRecipientName = ""

    var body: some View {
        LazyVStack(spacing: 10) {
            if store.lists.isEmpty && !showNewList {
                VStack(spacing: 14) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No swipe lists yet")
                        .font(.displaySmall)
                    Text("Make a list for someone — say, your girlfriend's birthday — then add finds from the feed or search. Send it and every swipe tells you buy / don't buy.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                .padding(.horizontal, 30)
            }

            if showNewList {
                newListCard
            } else {
                Button {
                    withAnimation(.spring(response: 0.3)) { showNewList = true }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                        Text("New swipe list")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                    .foregroundStyle(Color.coral)
                    .padding(14)
                    .background(Color.coralSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            ForEach(store.lists) { list in
                NavigationLink {
                    SwipeListDetailView(listId: list.id)
                } label: {
                    SwipeListRow(list: list)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var newListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEW SWIPE LIST")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            TextField("List name (e.g. Sarah's birthday)", text: $newListName)
                .textFieldStyle(.roundedBorder)
            TextField("Who's it for? (optional)", text: $newRecipientName)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                Button("Cancel") {
                    withAnimation(.spring(response: 0.3)) { showNewList = false }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                Spacer()
                Button {
                    let recipient = newRecipientName.trimmingCharacters(in: .whitespaces)
                    var name = newListName.trimmingCharacters(in: .whitespaces)
                    if name.isEmpty { name = recipient.isEmpty ? "New swipe list" : "For \(recipient)" }
                    store.createList(name: name, recipientName: recipient.isEmpty ? nil : recipient)
                    newListName = ""
                    newRecipientName = ""
                    withAnimation(.spring(response: 0.3)) { showNewList = false }
                } label: {
                    Text("Create")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 9)
                        .background(Color.coral)
                        .clipShape(Capsule())
                }
                .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty
                          && newRecipientName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct SwipeListRow: View {
    let list: SwipeList

    var body: some View {
        HStack(spacing: 12) {
            // Cover collage — up to three item thumbnails, Instagram-collection style.
            HStack(spacing: 2) {
                ForEach(Array(list.posts.prefix(3).enumerated()), id: \.offset) { _, post in
                    ZStack {
                        Color.gradient(for: post.product.grad)
                        if let image = post.product.image {
                            CachedAsyncImage(url: image, width: 120)
                        }
                    }
                    .frame(width: list.posts.count == 1 ? 56 : 27, height: 56)
                    .clipped()
                }
                if list.posts.isEmpty {
                    Image(systemName: "gift")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.coral)
                        .frame(width: 56, height: 56)
                        .background(Color.coralSoft)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                Text(list.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let recipient = list.recipientName, !recipient.isEmpty {
                        Text("for \(recipient) ·")
                    }
                    Text("\(list.posts.count) idea\(list.posts.count == 1 ? "" : "s")")
                    if list.challengeId != nil {
                        Text("· sent")
                            .foregroundStyle(Color.coral)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// One list: manage items, send it as a swipe deck, read the verdicts back.
struct SwipeListDetailView: View {
    let listId: String

    @ObservedObject private var store = SwipeListStore.shared
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var buildingLink = false
    @State private var shareFailed = false
    @State private var status: ChallengeStatusResponse?
    @State private var selectedPost: Post?

    private var list: SwipeList? { store.list(id: listId) }

    private var senderId: String {
        authManager.userId ?? InteractionQueue.anonymousUserId
    }

    var body: some View {
        ScrollView {
            if let list {
                VStack(alignment: .leading, spacing: 16) {
                    header(list)
                    shareCard(list)
                    if shareFailed {
                        Label("Couldn't build the swipe link — check your connection and try again.", systemImage: "wifi.slash")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    responsesSection(list)
                    itemsSection(list)
                }
                .padding(16)
            }
        }
        .background(Color.surface)
        .navigationTitle(list?.name ?? "Swipe list")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        store.deleteList(id: listId)
                        dismiss()
                    } label: {
                        Label("Delete list", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.ink)
                }
            }
        }
        .sheet(item: $selectedPost) { post in
            PostDetailView(post: post)
        }
        .task { await loadResponses() }
        .refreshable { await loadResponses() }
    }

    private func header(_ list: SwipeList) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let recipient = list.recipientName, !recipient.isEmpty {
                Text("For \(recipient)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.coral)
            }
            Text("They swipe right on what they'd love, left on what they wouldn't — you see every answer here. No guessing.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // The send card — the answer to "I added to a swipe list… now what?"
    @ViewBuilder
    private func shareCard(_ list: SwipeList) -> some View {
        let who = list.recipientName ?? "them"
        if list.posts.isEmpty {
            Label("Add finds from the feed or search — the “Add to swipe list” button on any product drops it here.", systemImage: "rectangle.stack.badge.plus")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cream)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else if let url = list.shareURL {
            ShareLink(item: url, message: Text(store.shareMessage(for: list))) {
                shareLabel(
                    title: "Send to \(who)",
                    subtitle: "They swipe your \(list.posts.count) picks in their browser — no app needed.",
                    icon: "paperplane.fill"
                )
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Task { await buildShareLink(list) }
            } label: {
                shareLabel(
                    title: buildingLink ? "Building their deck…" : (list.challengeId == nil ? "Get the swipe link" : "List changed — rebuild the link"),
                    subtitle: "Turns these \(list.posts.count) picks into a swipeable link for \(who).",
                    icon: "link"
                )
            }
            .buttonStyle(.plain)
            .disabled(buildingLink)
        }
    }

    private func shareLabel(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            if buildingLink {
                ProgressView()
                    .tint(.white)
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

    // ── Responses ─────────────────────────────────────────────────────────────

    @ViewBuilder
    private func responsesSection(_ list: SwipeList) -> some View {
        if list.challengeId != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Their swipes")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                let count = status?.responseCount ?? 0
                if count == 0 {
                    Text("No responses yet — they'll appear here the moment \(list.recipientName ?? "they") swipe(s).")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else if verdictsByPost.isEmpty {
                    // Responses exist but per-swipe detail is auth-gated
                    // (same hard boundary as challenge responses).
                    if authManager.isAuthenticated {
                        Text("\(count) response\(count == 1 ? "" : "s") in — verdicts load on refresh.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        SignInWall()
                    }
                } else {
                    Text("\(count) response\(count == 1 ? "" : "s") — the ✓/✕ on each item below are their answers.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.coral)
                }
            }
        }
    }

    // postId → guests' verdicts, from the sender-authenticated challenge view.
    private var verdictsByPost: [String: [(guest: String, yes: Bool)]] {
        var map: [String: [(guest: String, yes: Bool)]] = [:]
        for response in status?.responses ?? [] {
            let guest = response.guestName ?? "Friend"
            for swipe in response.swipes ?? [] {
                map[swipe.id, default: []].append((guest: guest, yes: swipe.dir == "yes"))
            }
        }
        return map
    }

    // ── Items ─────────────────────────────────────────────────────────────────

    private func itemsSection(_ list: SwipeList) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(list.posts.count) idea\(list.posts.count == 1 ? "" : "s")")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            ForEach(list.posts) { post in
                itemRow(post)
            }
        }
    }

    private func itemRow(_ post: Post) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedPost = post
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Color.gradient(for: post.product.grad)
                        Text(post.product.emoji).font(.system(size: 20))
                        if let image = post.product.image {
                            CachedAsyncImage(url: image, width: 200)
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(post.product.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            if post.product.price > 0 {
                                Text("$\(Int(post.product.price))")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.coral)
                            }
                            verdictBadges(for: post.id)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                store.remove(id: post.id, from: listId)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.cream)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove from list")
        }
    }

    // Their answer, right on the item: ✓ loved it / ✕ passed.
    @ViewBuilder
    private func verdictBadges(for postId: String) -> some View {
        if let verdicts = verdictsByPost[postId], !verdicts.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(verdicts.prefix(3).enumerated()), id: \.offset) { _, verdict in
                    HStack(spacing: 2) {
                        Image(systemName: verdict.yes ? "heart.fill" : "xmark")
                            .font(.system(size: 9, weight: .bold))
                        Text(verdict.guest)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(verdict.yes ? Color.coral : Color.inkSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(verdict.yes ? Color.coralSoft : Color.cream)
                    .clipShape(Capsule())
                }
            }
        }
    }

    // ── Networking ────────────────────────────────────────────────────────────

    // POST /challenges with deckMode "exact": the deck is EXACTLY this list —
    // client card snapshots ride along for items outside the vector index.
    private func buildShareLink(_ list: SwipeList) async {
        guard !list.posts.isEmpty, !buildingLink else { return }
        buildingLink = true
        defer { buildingLink = false }
        shareFailed = false

        let inviterName = authManager.displayName ?? "A friend"
        let cards: [[String: Any]] = list.posts.map { post in
            var card: [String: Any] = [
                "postId": post.id,
                "name": post.product.name,
                "price": post.product.price,
            ]
            if let image = post.product.image { card["image"] = image }
            if let url = post.productUrl ?? post.url { card["url"] = url }
            if let category = post.category { card["category"] = category }
            if let domain = post.domain { card["domain"] = domain }
            if let giftType = post.giftType { card["giftType"] = giftType }
            if let duration = post.serviceDuration { card["serviceDuration"] = duration }
            return card
        }

        do {
            let response = try await APIClient.shared.createChallenge(
                senderId: senderId,
                seedKeys: list.posts.map(\.id),
                inviterName: inviterName,
                to: list.recipientName,
                occasion: list.occasion,
                deckMode: "exact",
                cards: cards
            )
            guard let url = InviteLink.buildURL(
                inviterName: inviterName,
                senderId: senderId,
                to: list.recipientName,
                challengeId: response.challengeId
            ) else {
                shareFailed = true
                return
            }
            store.markShared(listId: list.id, challengeId: response.challengeId, url: url)
            AnalyticsEngine.shared.trackScreenView(screen: "swipe_list_shared")
        } catch {
            shareFailed = true
        }
    }

    private func loadResponses() async {
        guard let challengeId = list?.challengeId else { return }
        status = try? await APIClient.shared.fetchChallengeStatus(challengeId: challengeId)
    }
}
