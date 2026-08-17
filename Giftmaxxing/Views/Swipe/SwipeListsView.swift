import SwiftUI

// The "For someone" home: every Gift Board you keep, one per person/occasion
// (Instagram-collections model). Tap into a board to manage its items, send it
// as a swipe deck, and read the yes/no results back.
struct SwipeListsHomeView: View {
    // Embedders (the You-page Gift Boards tab) already pad their content —
    // they pass 0; the Swipe-tab home keeps the default gutter.
    var horizontalPadding: CGFloat = 20

    @ObservedObject private var store = SwipeListStore.shared
    @State private var showNewList = false
    @State private var newListName = ""
    @State private var newRecipientName = ""
    @State private var showAddByLink = false

    var body: some View {
        LazyVStack(spacing: 10) {
            // Boards a co-giver shared with you, waiting to be merged in.
            SharedBoardsRail()

            if store.lists.isEmpty && !showNewList {
                VStack(spacing: 14) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No Gift Boards yet")
                        .font(.displaySmall)
                    Text("Save finds for someone, send the board, and every swipe tells you buy or don't.")
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
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.3)) { showNewList = true }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                            Text("New board")
                                .font(.system(size: 14, weight: .bold))
                            Spacer()
                        }
                        .foregroundStyle(Color.coral)
                        .padding(14)
                        .background(Color.coralSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    // Paste any product URL → a card you can send. The fast way
                    // to build a board from links you already found while shopping.
                    Button {
                        showAddByLink = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .font(.system(size: 14, weight: .bold))
                            Text("Add by link")
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
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 12)
        .sheet(isPresented: $showAddByLink) {
            AddByLinkView()
        }
    }

    private var newListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEW GIFT BOARD")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            TextField("Board name (e.g. Sarah's birthday)", text: $newListName)
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
                    if name.isEmpty { name = recipient.isEmpty ? "New Gift Board" : "For \(recipient)" }
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
    // Note editor ("why this fits them") + the digital gift letter.
    @State private var editingNotePost: Post?
    @State private var editingLetter = false
    // In-app delivery — pick a friend, the board lands in their DMs.
    @State private var showFriendPicker = false
    @State private var showCoGiverPicker = false
    // Paste product links straight into THIS board.
    @State private var showAddByLink = false
    // Gift-graph traversal output: "Ideas for {name}" seeded by the board's
    // items + the recipient's own yes-swipes, filtered through relationship,
    // occasion, history, and time-to-occasion (GiftGraphRanker).
    @State private var graphIdeas: [Post] = []
    @State private var graphIdeasLoaded = false

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
                        Label("Couldn't build the share link — check your connection and try again.", systemImage: "wifi.slash")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    letterCard(list)
                    responsesSection(list)
                    graphIdeasSection(list)
                    itemsSection(list)
                }
                .padding(16)
            }
        }
        .background(Color.surface)
        .navigationTitle(list?.name ?? "Gift Board")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        store.deleteList(id: listId)
                        dismiss()
                    } label: {
                        Label("Delete board", systemImage: "trash")
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
        .sheet(isPresented: $showAddByLink) {
            AddByLinkView(targetListId: listId)
        }
        .sheet(item: $editingNotePost) { post in
            NoteEditorSheet(
                title: "Why this fits \(list?.recipientName ?? "them")",
                prompt: "e.g. She mentioned wanting one on our hike last fall…",
                text: list?.note(for: post.id) ?? ""
            ) { text in
                store.setNote(text, for: post.id, in: listId)
            }
        }
        .sheet(isPresented: $editingLetter) {
            NoteEditorSheet(
                title: "Gift letter for \(list?.recipientName ?? "them")",
                prompt: "The words outlast the wrapping — say what they mean to you…",
                text: list?.letter ?? "",
                long: true
            ) { text in
                store.setLetter(text, for: listId)
            }
        }
        .task {
            await loadResponses()
            await loadGraphIdeas()
        }
        .refreshable {
            await loadResponses()
            await loadGraphIdeas(force: true)
        }
    }

    // The digital gift letter — written once, sent with the board.
    @ViewBuilder
    private func letterCard(_ list: SwipeList) -> some View {
        if let letter = list.letter, !letter.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Gift letter", systemImage: "envelope.open.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.coral)
                    Spacer()
                    Button("Edit") { editingLetter = true }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.coral)
                }
                Text(letter)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink)
                    .lineLimit(6)
                Text("Sent along with the board's share message.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.cream)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            Button {
                editingLetter = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.coral)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Write a digital gift letter")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.ink)
                        Text("Rides along when you send the board. +40 pts")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color.cream)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    private static let relationshipOptions = ["Partner", "Parent", "Sibling", "Best friend", "Colleague", "Friend"]

    private func header(_ list: SwipeList) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let recipient = list.recipientName, !recipient.isEmpty {
                    Text("For \(recipient)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.coral)
                }
                // Relationship = the primary edge of the gift graph — one tap
                // here sharpens the "Ideas for them" traversal below.
                Menu {
                    ForEach(Self.relationshipOptions, id: \.self) { option in
                        Button(option) {
                            store.setRelationship(option.lowercased(), for: listId)
                            Task { await loadGraphIdeas(force: true) }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(list.relationship?.capitalized ?? "Relationship?")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(list.relationship == nil ? Color.coral : Color.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(list.relationship == nil ? Color.coralSoft : Color.cream)
                    .clipShape(Capsule())
                }
                Spacer()
            }
            Text("Their swipes land here — no guessing.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    // The send card — the answer to "I added to a swipe list… now what?"
    @ViewBuilder
    private func shareCard(_ list: SwipeList) -> some View {
        let who = list.recipientName ?? "them"
        // Two people shopping for the same person: hand them the board so they
        // can add their picks before either of you sends the deck.
        Button {
            showCoGiverPicker = true
        } label: {
            shareLabel(
                title: "Build it with someone",
                subtitle: "Share this board with a partner or co-giver so they can add ideas too.",
                icon: "person.2.badge.plus"
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showCoGiverPicker) {
            FriendPickerSheet(
                messageText: "I started a gift board — \"\(list.name)\". Add your ideas and we'll send it together."
            ) { friendId in
                Task { await shareBoardWithCoGiver(list, friendId: friendId) }
            }
            .environmentObject(authManager)
        }

        if list.posts.isEmpty {
            Label("Add finds from the feed or search — the “Gift board” button on any product drops it here.", systemImage: "rectangle.stack.badge.plus")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cream)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else if let url = list.shareURL {
            VStack(spacing: 8) {
                // In-app first: a friend with Giftmaxxing swipes the board
                // natively via DM — no browser.
                Button {
                    showFriendPicker = true
                } label: {
                    shareLabel(
                        title: "Send to \(who) in the app",
                        subtitle: "They swipe your \(list.posts.count) picks right here — no browser.",
                        icon: "person.crop.circle.badge.checkmark"
                    )
                }
                .buttonStyle(.plain)

                ShareLink(item: url, message: Text(store.shareMessage(for: list))) {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 13))
                        Text("Share outside the app (link works in any browser)")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Color.coral)
                    .padding(12)
                    .background(Color.coralSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .sheet(isPresented: $showFriendPicker) {
                FriendPickerSheet(
                    messageText: "\(store.shareMessage(for: list))\n\(url.absoluteString)"
                ) { friendId in
                    // They have the app: the list also lands in their in-app
                    // inbox with a push, not just as a link in the thread.
                    guard let challengeId = list.challengeId else { return }
                    Task {
                        try? await APIClient.shared.inviteToChallenge(
                            challengeId: challengeId,
                            toUserId: friendId,
                            byUserId: authManager.userId,
                            byName: authManager.displayName,
                            title: list.name
                        )
                    }
                }
                .environmentObject(authManager)
            }
        } else {
            Button {
                Task { await buildShareLink(list) }
            } label: {
                shareLabel(
                    title: buildingLink ? "Building their deck…" : (list.challengeId == nil ? "Get the share link" : "Board changed — rebuild the link"),
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
            HStack {
                Text("\(list.posts.count) idea\(list.posts.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    showAddByLink = true
                } label: {
                    Label("Add by link", systemImage: "link")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.coral)
                }
            }

            boughtProgress(list)

            ForEach(list.posts) { post in
                itemRow(post, bought: list.isBought(post.id))
            }
        }
    }

    // Private purchase checklist tally — how many of these you've bought. Only
    // you see this; it never rides along in the deck the recipient swipes.
    @ViewBuilder
    private func boughtProgress(_ list: SwipeList) -> some View {
        let total = list.posts.count
        let bought = list.boughtCount
        if total > 0 && bought > 0 {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: bought == total ? "checkmark.seal.fill" : "checklist")
                        .font(.system(size: 12, weight: .bold))
                    Text(bought == total ? "All \(total) bought 🎉" : "\(bought) of \(total) bought")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Color.coral)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.coralSoft).frame(height: 5)
                        Capsule().fill(Color.coral)
                            .frame(width: geo.size.width * CGFloat(bought) / CGFloat(total), height: 5)
                    }
                }
                .frame(height: 5)
            }
            .padding(.bottom, 2)
        }
    }

    private func itemRow(_ post: Post, bought: Bool) -> some View {
        HStack(spacing: 12) {
            // Private "bought" checkbox — tap to check off a gift you've
            // purchased. Registry-style, so you can see at a glance what's left.
            Button {
                store.toggleBought(post.id, in: listId)
            } label: {
                Image(systemName: bought ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(bought ? Color.coral : Color.inkSecondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(bought ? "Mark \(post.product.name) as not bought" : "Mark \(post.product.name) as bought")

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
                            .strikethrough(bought, color: Color.inkSecondary)
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
                        // The "why this fits them" note — or the nudge to write one.
                        if let note = list?.note(for: post.id) {
                            Text("“\(note)”")
                                .font(.system(size: 12))
                                .italic()
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .opacity(bought ? 0.55 : 1)

            Spacer()

            VStack(spacing: 8) {
                Button {
                    editingNotePost = post
                } label: {
                    Image(systemName: list?.note(for: post.id) == nil ? "square.and.pencil" : "square.and.pencil.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(list?.note(for: post.id) == nil ? Color.coral : Color.coral.opacity(0.9))
                        .frame(width: 28, height: 28)
                        .background(Color.coralSoft)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Write why this fits them")

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
                .accessibilityLabel("Remove from board")
            }
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
    // Snapshot the board to a co-giver: they get a push, it lands in their
    // "Shared with you" rail, and accepting merges the items into their boards.
    private func shareBoardWithCoGiver(_ list: SwipeList, friendId: String) async {
        var payload: [String: Any] = ["name": list.name]
        if let recipient = list.recipientName { payload["recipientName"] = recipient }
        if let occasion = list.occasion { payload["occasion"] = occasion }
        if let relationship = list.relationship { payload["relationship"] = relationship }
        payload["posts"] = list.posts.prefix(100).map { post -> [String: Any] in
            var item: [String: Any] = ["postId": post.id, "name": post.product.name]
            if let image = post.product.image { item["image"] = image }
            if post.product.price > 0 { item["price"] = post.product.price }
            if !post.product.brand.isEmpty { item["brand"] = post.product.brand }
            if let url = post.productUrl ?? post.url { item["productUrl"] = url }
            return item
        }
        try? await APIClient.shared.shareBoard(
            toUserId: friendId,
            board: payload,
            byUserId: authManager.userId,
            byName: authManager.displayName
        )
    }

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

    // ── Gift-graph ideas ("more like what fits THEM") ─────────────────────

    @ViewBuilder
    private func graphIdeasSection(_ list: SwipeList) -> some View {
        if !graphIdeas.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ideas for \(list.recipientName ?? "them")")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(graphIdeas) { post in
                            Button {
                                selectedPost = post
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    ZStack {
                                        Color.gradient(for: post.product.grad)
                                        if let image = post.product.image {
                                            CachedAsyncImage(url: image, width: 300)
                                        }
                                    }
                                    .frame(width: 110, height: 110)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    Text(post.product.name)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.ink)
                                        .lineLimit(1)
                                        .frame(width: 110, alignment: .leading)
                                    if let reason = post.reason {
                                        Text(reason)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.coral)
                                            .lineLimit(1)
                                            .frame(width: 110, alignment: .leading)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // Traverse the graph: board items + the recipient's yes-swipes seed a kNN,
    // then GiftGraphRanker re-scores by relationship, interests, feedback,
    // history, time-to-occasion, and the giver's mindset.
    private func loadGraphIdeas(force: Bool = false) async {
        guard let list, !list.posts.isEmpty else { return }
        if graphIdeasLoaded && !force { return }
        graphIdeasLoaded = true

        let userId = authManager.userId ?? InteractionQueue.anonymousUserId
        let connections = (try? await APIClient.shared.fetchConnections(userId: userId)) ?? []
        let events = (try? await APIClient.shared.fetchUpcomingEvents(userId: userId)) ?? []

        let context = RecipientGraphContext.build(
            for: list,
            allBoards: store.lists,
            pools: PoolsStore.shared.pools,
            connections: connections,
            events: events
        )

        // Seed the kNN with the board's items + the recipient's own yes-swipes.
        let seedKeys = Array((list.posts.map(\.id) + context.feedbackSeedIds).prefix(8))
        guard let response = try? await APIClient.shared.fetchVectorRecommendations(seedKeys: seedKeys, limit: 24),
              let items = response.items, !items.isEmpty else { return }

        let boardIds = Set(list.posts.map(\.id))
        let candidates: [Post] = items
            .filter { !boardIds.contains($0.postId) }
            .map { item in
                Post(
                    id: item.postId,
                    user: item.author ?? "giftmaxxing",
                    time: "",
                    product: Product(
                        id: item.postId,
                        name: item.name ?? "Gift idea",
                        brand: item.merchant ?? item.source ?? "",
                        price: item.price ?? 0,
                        grad: .coral,
                        emoji: "🎁",
                        image: item.image
                    ),
                    caption: "",
                    likes: 0,
                    productUrl: item.productUrl ?? item.url,
                    domain: item.domain,
                    giftType: item.giftType,
                    serviceDuration: item.serviceDuration
                )
            }

        // Ground truth: similarity of each candidate to the centroid of what
        // this recipient swiped YES on (device-cached Titan vectors).
        var feedbackSimilarities: [String: Float] = [:]
        if context.feedbackSeedIds.count >= 2 {
            let allKeys = context.feedbackSeedIds + candidates.map(\.id)
            let missing = await VectorStore.shared.missingKeys(from: allKeys)
            if !missing.isEmpty, let vectors = try? await APIClient.shared.fetchVectors(keys: missing) {
                for item in vectors.items ?? [] {
                    await VectorStore.shared.upsert(key: item.key, base64: item.data, scale: item.scale)
                }
            }
            if let centroid = await VectorStore.shared.centroid(of: context.feedbackSeedIds) {
                feedbackSimilarities = await VectorStore.shared.similarities(keys: candidates.map(\.id), to: centroid)
            }
        }

        let base = candidates.map { RankedCandidate(post: $0, score: $0.qualityScore ?? 0.5, reason: nil) }
        let traversed = GiftGraphRanker.traverse(
            base,
            context: context,
            mindset: GiftMindset.current(),
            feedbackSimilarities: feedbackSimilarities
        )
        graphIdeas = traversed.prefix(10).map { candidate in
            var post = candidate.post
            if post.reason == nil { post.reason = candidate.reason }
            return post
        }
    }
}

// Shared editor for board notes and the gift letter — plain, focused writing.
struct NoteEditorSheet: View {
    let title: String
    let prompt: String
    @State var text: String
    var long = false
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text(prompt)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .focused($focused)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: long ? 220 : 120)
                    .background(Color.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Spacer()
            }
            .padding(16)
            .background(Color.surface)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.coral)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([long ? .large : .medium])
    }
}
