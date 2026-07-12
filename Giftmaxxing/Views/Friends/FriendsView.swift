import SwiftUI

/// Friends hub — iOS port of web/app/feed/friends/page.tsx.
/// Tabs: Friends / Requests / Discover. Connect, message, and gift.
struct FriendsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = FriendsStore.shared
    @State private var tab: FriendsTab = .friends
    @State private var query = ""
    @State private var busyId: String?
    @State private var openThreadId: String?
    @State private var showDm = false

    private enum FriendsTab: String, CaseIterable {
        case friends = "Friends"
        case requests = "Requests"
        case discover = "Discover"
    }

    private var userId: String? { authManager.userId }

    private var incoming: [Friendship] {
        store.pending.filter { $0.incoming == true || ($0.requestedBy != nil && $0.requestedBy != userId) }
    }

    private var outgoing: [Friendship] {
        store.pending.filter { $0.incoming != true && $0.requestedBy == userId }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(FriendsTab.allCases, id: \.self) { t in
                    Text(label(for: t)).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if tab == .discover {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search people by name or handle…", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await refresh() } }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(Capsule())
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    switch tab {
                    case .friends: friendsList
                    case .requests: requestsList
                    case .discover: discoverList
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color.surface)
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
        .navigationDestination(isPresented: $showDm) {
            if let openThreadId {
                FriendDmThreadView(threadId: openThreadId)
            }
        }
        .onAppear {
            AnalyticsEngine.shared.trackScreenView(screen: "friends")
        }
    }

    private func label(for tab: FriendsTab) -> String {
        switch tab {
        case .friends:
            return store.friends.isEmpty ? "Friends" : "Friends (\(store.friends.count))"
        case .requests:
            return incoming.isEmpty ? "Requests" : "Requests (\(incoming.count))"
        case .discover:
            return "Discover"
        }
    }

    // MARK: - Lists

    @ViewBuilder
    private var friendsList: some View {
        if store.friends.isEmpty {
            emptyState(
                title: "No friends yet",
                body: "Discover people who have the app, or connect inside a shared circle.",
                cta: "Discover people"
            ) { tab = .discover }
        } else {
            ForEach(store.friends) { friend in
                PersonRow(
                    name: friend.name ?? friend.friendId,
                    handle: friend.handle,
                    interests: friend.interests,
                    grad: SocialUsers.grad(for: friend.friendId)
                ) {
                    HStack(spacing: 6) {
                        Button("Message") {
                            Task { await message(friend.friendId) }
                        }
                        .buttonStyle(FriendPillStyle(filled: true))
                        .disabled(busyId == friend.friendId)

                        Button("Gift") {
                            appState.selectedTab = .feed
                        }
                        .buttonStyle(FriendPillStyle(coral: true))

                        Button("Remove") {
                            Task { await remove(friend.friendId) }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var requestsList: some View {
        if incoming.isEmpty && outgoing.isEmpty {
            emptyState(title: "No pending requests", body: "When someone adds you, it'll show up here.", cta: nil, action: nil)
        } else {
            if !incoming.isEmpty {
                sectionHeader("INCOMING")
                ForEach(incoming) { friend in
                    PersonRow(
                        name: friend.name ?? friend.friendId,
                        handle: friend.handle,
                        interests: nil,
                        grad: SocialUsers.grad(for: friend.friendId)
                    ) {
                        HStack(spacing: 6) {
                            Button("Accept") {
                                Task { await accept(friend.friendId) }
                            }
                            .buttonStyle(FriendPillStyle(coral: true))
                            Button("Decline") {
                                Task { await remove(friend.friendId) }
                            }
                            .buttonStyle(FriendPillStyle(filled: false))
                        }
                    }
                }
            }
            if !outgoing.isEmpty {
                sectionHeader("SENT")
                ForEach(outgoing) { friend in
                    PersonRow(
                        name: friend.name ?? friend.friendId,
                        handle: friend.handle,
                        interests: nil,
                        grad: SocialUsers.grad(for: friend.friendId)
                    ) {
                        Text("Pending")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var discoverList: some View {
        sectionHeader(query.isEmpty ? "PEOPLE ON GIFTMAXXING" : "RESULTS")
        if store.discover.isEmpty {
            emptyState(
                title: "Nobody matched",
                body: "Try another name, or finish your taste profile so friends can find you.",
                cta: "Edit my taste"
            ) {
                // Handled via NavigationLink below when needed
            }
            NavigationLink("Edit my taste") {
                OnboardingView()
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.coral)
            .padding(.top, 8)
        } else {
            let friendIds = Set(store.friends.map(\.friendId))
            let pendingIds = Set(store.pending.map(\.friendId))
            ForEach(store.discover) { person in
                PersonRow(
                    name: person.name,
                    handle: person.handle,
                    interests: person.interests,
                    grad: SocialUsers.grad(for: person.userId)
                ) {
                    if friendIds.contains(person.userId) {
                        Button("Message") {
                            Task { await message(person.userId) }
                        }
                        .buttonStyle(FriendPillStyle(filled: true))
                    } else if pendingIds.contains(person.userId) {
                        Text("Requested")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Add friend") {
                            Task { await request(person) }
                        }
                        .buttonStyle(FriendPillStyle(coral: true))
                        .disabled(busyId == person.userId || userId == nil)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func refresh() async {
        await store.refresh(userId: userId, query: query)
    }

    private func request(_ person: PublicPerson) async {
        guard let userId else { return }
        busyId = person.userId
        await store.requestFriend(
            fromUserId: userId,
            toUserId: person.userId,
            toName: person.name,
            toHandle: person.handle
        )
        busyId = nil
    }

    private func accept(_ fromUserId: String) async {
        guard let userId else { return }
        busyId = fromUserId
        await store.acceptFriend(userId: userId, fromUserId: fromUserId)
        busyId = nil
    }

    private func remove(_ friendId: String) async {
        guard let userId else { return }
        busyId = friendId
        await store.removeFriend(userId: userId, friendId: friendId)
        busyId = nil
    }

    private func message(_ otherId: String) async {
        guard let userId else { return }
        busyId = otherId
        if let tid = await store.openDm(userId: userId, otherUserId: otherId) {
            openThreadId = tid
            showDm = true
        }
        busyId = nil
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private func emptyState(title: String, body: String, cta: String?, action: (() -> Void)?) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.displaySmall)
                .foregroundStyle(Color.ink)
            Text(body)
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let cta, let action {
                Button(cta, action: action)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.coral)
                    .clipShape(Capsule())
                    .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared row / styles

private struct PersonRow<Actions: View>: View {
    let name: String
    let handle: String?
    let interests: [String]?
    let grad: GradientStyle
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: name, grad: grad, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                if let handle, !handle.isEmpty {
                    Text("@\(handle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let interests, !interests.isEmpty {
                    Text(interests.prefix(3).joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            actions()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct FriendPillStyle: ButtonStyle {
    var filled = false
    var coral = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(filled || coral ? Color.white : Color.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(coral ? Color.coral : (filled ? Color.ink : Color.cream))
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - DM thread

struct FriendDmThreadView: View {
    let threadId: String

    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var store = FriendsStore.shared
    @State private var messages: [DmMessage] = []
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var thread: DmThread? {
        store.dms.first { $0.threadId == threadId }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if messages.isEmpty {
                            Text("You're friends — say hi, or gift them something from the feed.")
                                .font(.bodyMedium)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(40)
                        }
                        ForEach(messages) { msg in
                            dmBubble(msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            HStack(spacing: 10) {
                TextField("Type a message…", text: $draft)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .focused($focused)
                if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.coral)
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.surface)
        }
        .background(Color.surface)
        .navigationTitle(thread?.otherName ?? "Friend")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("DM")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .task { await load() }
    }

    private func dmBubble(_ msg: DmMessage) -> some View {
        let isMe = msg.userId == authManager.userId || msg.userId == "you"
        return HStack {
            if isMe { Spacer(minLength: 40) }
            VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                if !isMe {
                    Text(msg.name)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Text(msg.text)
                    .font(.system(size: 14))
                    .foregroundStyle(isMe ? Color.white : Color.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isMe ? Color.coral : Color.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            if !isMe { Spacer(minLength: 40) }
        }
    }

    private func load() async {
        messages = await store.messages(for: threadId)
    }

    private func send() async {
        guard let userId = authManager.userId else { return }
        let name = authManager.displayName ?? "You"
        let text = draft
        draft = ""
        if let msg = await store.sendMessage(threadId: threadId, userId: userId, name: name, text: text) {
            messages.append(msg)
        }
    }
}
