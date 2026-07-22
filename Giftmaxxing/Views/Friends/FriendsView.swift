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
    @State private var challengeFriendName: String?
    @State private var showChallenge = false

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
        .sheet(isPresented: $showChallenge) {
            NavigationStack {
                ChallengeView(
                    showsClose: true,
                    prefillTheirName: challengeFriendName ?? ""
                )
            }
            .environmentObject(appState)
            .environmentObject(authManager)
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
                VStack(alignment: .leading, spacing: 10) {
                    PersonRow(
                        name: friend.name ?? friend.friendId,
                        handle: friend.handle,
                        interests: friend.interests,
                        grad: SocialUsers.grad(for: friend.friendId)
                    ) {
                        // The friend's full gifting profile — sizes, dislikes,
                        // and the gifts they'd love (friend-gated server-side).
                        NavigationLink {
                            PublicProfileView(person: PublicPerson(
                                userId: friend.friendId,
                                name: friend.name ?? friend.friendId,
                                handle: friend.handle ?? "",
                                bio: friend.bio,
                                interests: friend.interests
                            ))
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.coral)
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            Task { await message(friend.friendId) }
                        } label: {
                            Label("Message", systemImage: "bubble.left.fill")
                        }
                        .buttonStyle(FriendPillStyle(filled: true))
                        .disabled(busyId == friend.friendId)

                        Button {
                            challengeFriendName = friend.name ?? friend.handle ?? friend.friendId
                            showChallenge = true
                        } label: {
                            Label("Challenge", systemImage: "gift.fill")
                        }
                        .buttonStyle(FriendPillStyle(coral: true))

                        Spacer(minLength: 0)

                        Button("Remove") {
                            Task { await remove(friend.friendId) }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
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
                TasteInterviewView()
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
                    NavigationLink {
                        PublicProfileView(person: person)
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.coral)
                    }
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

private extension View {
    func profileStatusChip() -> some View {
        font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.coral)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.coralSoft)
            .clipShape(Capsule())
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

/// Public search results lead to this compact, share-safe profile. The API
/// returns a private profile here only when the viewer is an accepted friend.
/// Beyond the persona, this is the "gift them right" page: their sizes,
/// dislikes, standing note, and photos of gifts they'd love.
struct PublicProfileView: View {
    let person: PublicPerson
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = FriendsStore.shared
    @State private var profile: PublicPerson?
    @State private var relationship = "none"
    @State private var busy = false
    @State private var threadId: String?
    @State private var showDm = false
    @State private var showGiftConsult = false
    @State private var showGiftList = false
    @State private var showGroupGift = false
    @State private var selectedPost: UGCPost?

    private var displayed: PublicPerson { profile ?? person }
    private var isFriend: Bool { relationship == "accepted" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                profileHeader
                relationshipActions
                giftListSection
                postsSection
            }
            .padding(16)
        }
        .background(Color.cream)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "publicProfilePreview") {
                ToolbarItem(placement: .topBarLeading) {
                    Button {} label: { Image(systemName: "chevron.left") }
                }
            }
            #endif
            if isFriend {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Invite to group gift", systemImage: "person.3.fill") { showGroupGift = true }
                        Button("Remove friend", systemImage: "person.badge.minus", role: .destructive) {
                            Task { await removeFriend() }
                        }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
        }
        .navigationDestination(isPresented: $showDm) {
            if let threadId { FriendDmThreadView(threadId: threadId) }
        }
        .sheet(isPresented: $showGiftConsult) {
            NavigationStack { ConsultView(skipIntro: true, prefillRecipientName: displayed.name) }
        }
        .sheet(isPresented: $showGiftList) {
            FriendGiftListView(name: displayed.name, items: displayed.giftShowcase ?? [])
        }
        .sheet(isPresented: $showGroupGift) {
            NavigationStack { GroupGiftCreateView(prefillRecipient: displayed.name) }
                .environmentObject(appState)
                .environmentObject(authManager)
        }
        .sheet(item: $selectedPost) { UGCProfilePostSheet(post: $0) }
        .task {
            profile = try? await APIClient.shared.fetchPerson(userId: person.userId)
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "publicProfilePreview") {
                var preview = profile ?? person
                preview.tagline = preview.tagline ?? "Thoughtful gifts. Meaning that lasts."
                preview.clothingSizes = preview.clothingSizes ?? ["shirt": "M", "shoes": "8.5", "pants": "28"]
                preview.interests = preview.interests ?? ["foodie", "luxury", "thoughtful"]
                preview.dislikes = preview.dislikes ?? ["candles"]
                if preview.giftShowcase?.isEmpty != false {
                    preview.giftShowcase = [
                        GiftShowcaseItem(
                            postId: "preview-jacket",
                            name: "Hourglass Work Jacket",
                            imageUrl: "https://cdn.shopify.com/s/files/1/0293/9277/files/V225JK0709_Black_JR_V1.jpg?width=1200",
                            brand: "Fashion Nova",
                            price: 36,
                            productUrl: "https://www.fashionnova.com/products/own-the-room-hourglass-twill-work-jacket-fncolorname-black"
                        ),
                        GiftShowcaseItem(
                            postId: "preview-top",
                            name: "Poise Crew Neck Top",
                            imageUrl: "https://cdn.shopify.com/s/files/1/0156/6146/files/BalletTightCrewNeckTopGSCoolBrownB4C4P_NBZG_0441.jpg?width=1200",
                            brand: "Gymshark",
                            price: 38,
                            productUrl: "https://www.gymshark.com/products/gymshark-poise-crew-neck-short-sleeve-top-ss-tops-brown-ss26"
                        ),
                    ]
                }
                profile = preview
                relationship = "accepted"
                return
            }
            #endif
            if let userId = authManager.userId {
                relationship = await store.status(userId: userId, otherId: person.userId)
            }
        }
    }

    private var profileHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            AvatarView(
                name: displayed.name,
                grad: SocialUsers.grad(for: displayed.userId),
                size: 92,
                imageUrl: displayed.imageUrl,
                anonymousFallback: true
            )
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Label("\(displayed.friendCount ?? 0) friends", systemImage: "person.2.fill")
                        .profileStatusChip()
                    if isFriend {
                        Label("Gift friends", systemImage: "heart.fill")
                            .profileStatusChip()
                    }
                }
                Text(displayed.name).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Color.ink)
                Text("@\(displayed.handle)").font(.subheadline).foregroundStyle(Color.inkSecondary)
                if let tagline = displayed.tagline, !tagline.isEmpty {
                    Text(tagline).font(.system(size: 13)).foregroundStyle(Color.ink)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    @ViewBuilder private var relationshipActions: some View {
        if isFriend {
            HStack(spacing: 10) {
                Button { showGiftConsult = true } label: { Label("Send a gift", systemImage: "gift.fill") }
                    .buttonStyle(ProfilePrimaryButtonStyle())
                Button { Task { await message() } } label: { Label("Message", systemImage: "bubble.left.fill") }
                    .buttonStyle(ProfileSecondaryButtonStyle())
                    .disabled(busy)
            }
        } else {
            Button {
                Task { await updateFriendship() }
            } label: {
                Label(friendshipLabel, systemImage: relationship == "incoming" ? "person.badge.checkmark" : "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ProfilePrimaryButtonStyle())
            .disabled(busy || relationship == "pending")
            Text("Gift lists, messaging, and group gift invites unlock after you’re friends.")
                .font(.caption).foregroundStyle(Color.inkSecondary)
        }
    }

    private var friendshipLabel: String {
        switch relationship {
        case "incoming": "Accept friend"
        case "pending": "Requested"
        default: "Add friend"
        }
    }

    @ViewBuilder private var giftListSection: some View {
        if let showcase = displayed.giftShowcase, !showcase.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("GIFT IDEAS FOR ME").font(.system(size: 12, weight: .bold)).tracking(1.2).foregroundStyle(Color.inkSecondary)
                    Spacer()
                    if isFriend {
                        Button("See all") { showGiftList = true }
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.coral)
                    }
                }
                HStack(spacing: 10) {
                    ForEach(showcase.prefix(2)) { giftCard($0) }
                }
            }
        }
    }

    private func giftCard(_ item: GiftShowcaseItem) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Color.surfaceSunken
                if let image = item.imageUrl { CachedAsyncImage(url: image, width: 360) }
                else { Image(systemName: "gift.fill").foregroundStyle(Color.coral) }
            }
            .frame(width: 82, height: 82).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.name ?? "Gift idea").font(.system(size: 13, weight: .bold)).lineLimit(2)
                Text(item.brand ?? "Saved find").font(.caption).foregroundStyle(Color.inkSecondary).lineLimit(1)
                if let price = item.price, price > 0 {
                    Text(price, format: .currency(code: "USD")).font(.caption).foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var tasteSection: some View {
        let sizes = displayed.clothingSizes ?? [:]
        let vibes = displayed.interests ?? []
        if !sizes.isEmpty || !vibes.isEmpty || !(displayed.dislikes ?? []).isEmpty || !(displayed.giftNote ?? "").isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !sizes.isEmpty {
                    sectionTitle("Measurements")
                    HStack(spacing: 0) {
                        ForEach(orderedSizes(sizes), id: \.0) { key, value in
                            HStack(spacing: 7) {
                                Image(systemName: sizeIcon(key)).font(.title3).foregroundStyle(Color.coral)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(key.capitalized).font(.caption).foregroundStyle(Color.inkSecondary)
                                    Text(value).font(.system(size: 17, weight: .bold, design: .rounded))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
                if !vibes.isEmpty {
                    Text("Gift vibes").font(.system(size: 14, weight: .bold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(vibes.prefix(6), id: \.self) { vibe in
                                Text(vibe).font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(Color.coralSoft).clipShape(Capsule())
                            }
                        }
                    }
                }
                if let note = displayed.giftNote, !note.isEmpty { Label(note, systemImage: "info.circle").font(.system(size: 13)) }
                if let dislikes = displayed.dislikes, !dislikes.isEmpty {
                    Label("Please avoid   \(dislikes.joined(separator: " · "))", systemImage: "minus.circle")
                        .font(.system(size: 13)).foregroundStyle(Color.inkSecondary)
                }
                Divider()
            }
        }
    }

    @ViewBuilder private var postsSection: some View {
        if let posts = displayed.posts, !posts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Posts", action: "\(posts.count) live")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                    ForEach(posts) { post in
                        Button { selectedPost = post } label: {
                            ZStack {
                                Color.surfaceSunken
                                CachedAsyncImage(url: post.posterUrl ?? post.mediaUrl, width: 280)
                                if post.mediaType == "video" {
                                    Image(systemName: "play.fill").font(.caption.bold()).foregroundStyle(.white)
                                        .padding(7).background(.black.opacity(0.55)).clipShape(Circle())
                                }
                            }
                            .aspectRatio(1, contentMode: .fill).clipped()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.md, style: .continuous))
            }
        }
    }

    private func sectionTitle(_ title: String, action: String? = nil) -> some View {
        HStack {
            Text(title.uppercased()).font(.system(size: 12, weight: .bold)).tracking(1.2).foregroundStyle(Color.inkSecondary)
            Spacer()
            if let action { Text(action).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.coral) }
        }
    }

    private func profileCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func orderedSizes(_ sizes: [String: String]) -> [(String, String)] {
        let order = ["shirt", "shoes", "pants", "dress", "ring"]
        return sizes.sorted {
            (order.firstIndex(of: $0.key.lowercased()) ?? 99) < (order.firstIndex(of: $1.key.lowercased()) ?? 99)
        }.prefix(3).map { ($0.key, $0.value) }
    }

    private func sizeIcon(_ key: String) -> String {
        switch key.lowercased() {
        case "shirt": "tshirt.fill"
        case "shoes", "shoe": "shoe.2.fill"
        default: "ruler.fill"
        }
    }

    private func updateFriendship() async {
        guard let userId = authManager.userId else { return }
        busy = true
        if relationship == "incoming" {
            await store.acceptFriend(userId: userId, fromUserId: displayed.userId)
        } else {
            await store.requestFriend(fromUserId: userId, toUserId: displayed.userId, toName: displayed.name, toHandle: displayed.handle)
        }
        relationship = await store.status(userId: userId, otherId: displayed.userId)
        profile = try? await APIClient.shared.fetchPerson(userId: displayed.userId)
        busy = false
    }

    private func message() async {
        guard isFriend, let userId = authManager.userId else { return }
        busy = true
        threadId = await store.openDm(userId: userId, otherUserId: displayed.userId)
        showDm = threadId != nil
        busy = false
    }

    private func removeFriend() async {
        guard let userId = authManager.userId else { return }
        await store.removeFriend(userId: userId, friendId: displayed.userId)
        relationship = "none"
    }
}

private struct ProfilePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(Color.coral).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct ProfileSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(Color.surface).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.line))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct FriendGiftListView: View {
    let name: String
    let items: [GiftShowcaseItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    ForEach(items) { item in
                        Group {
                            if let value = item.productUrl, let url = URL(string: value) {
                                Link(destination: url) { card(item) }
                            } else {
                                card(item)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.cream)
            .navigationTitle("\(name)’s gift list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func card(_ item: GiftShowcaseItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                Color.surfaceSunken
                if let image = item.imageUrl { CachedAsyncImage(url: image, width: 420) }
                else { Image(systemName: "gift.fill").foregroundStyle(Color.coral) }
            }
            .aspectRatio(1, contentMode: .fill).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(item.name ?? "Gift idea").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.ink).lineLimit(2)
            HStack {
                Text(item.brand ?? "Saved find").lineLimit(1)
                Spacer()
                if let price = item.price, price > 0 { Text(price, format: .currency(code: "USD")) }
            }
            .font(.caption).foregroundStyle(Color.inkSecondary)
        }
        .padding(10).background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
    }
}

// MARK: - DM thread

struct FriendDmThreadView: View {
    let threadId: String

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = FriendsStore.shared
    @State private var messages: [DmMessage] = []
    @State private var draft = ""
    @State private var showChallenge = false
    // A challenge invite in this thread, opened natively (no web bounce).
    @State private var inAppChallenge: ChallengeRef?
    @FocusState private var focused: Bool

    private var thread: DmThread? {
        store.dms.first { $0.threadId == threadId }
    }

    private var friendDisplayName: String {
        thread?.otherName ?? thread?.otherUserId ?? "Friend"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if messages.isEmpty {
                            Text("You're friends — say hi, or send a gift challenge so they swipe what they'd love.")
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
                .refreshable { await load() }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }

            // Gift-challenge shortcut — same action as Friends "Challenge"
            HStack(spacing: 8) {
                Button {
                    showChallenge = true
                } label: {
                    Label("Send gift challenge", systemImage: "gift.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.coral)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.coral.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)

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
        .navigationTitle(friendDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showChallenge = true
                } label: {
                    Image(systemName: "gift.fill")
                        .foregroundStyle(Color.coral)
                }
                .accessibilityLabel("Send gift challenge")
            }
        }
        .sheet(isPresented: $showChallenge) {
            NavigationStack {
                ChallengeView(
                    showsClose: true,
                    prefillTheirName: friendDisplayName,
                    dmThreadId: threadId
                )
            }
            .environmentObject(appState)
            .environmentObject(authManager)
        }
        .sheet(item: $inAppChallenge) { ref in
            ChallengeSwipeView(challengeId: ref.id)
                .environmentObject(authManager)
        }
        .task {
            appState.suppressMaxiFAB()
            await load()
            // Near-real-time: poll while this chat is open so peer messages appear
            // without leaving and coming back.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await load(silent: true)
            }
        }
        .onDisappear { appState.unsuppressMaxiFAB() }
    }

    private func dmBubble(_ msg: DmMessage) -> some View {
        let isMe = msg.userId == authManager.userId || msg.userId == "you"
        let sharedURL = Self.firstURL(in: msg.text)
        let bodyText = msg.text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { URL(string: $0)?.scheme == nil }
            .joined(separator: " ")
        return HStack {
            if isMe { Spacer(minLength: 40) }
            VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                if !isMe {
                    Text(msg.name)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Text(bodyText.isEmpty ? "Shared a gift challenge" : bodyText)
                    .font(.system(size: 14))
                    .foregroundStyle(isMe ? Color.white : Color.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isMe ? Color.coral : Color.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                if let sharedURL {
                    // Challenge invites open the NATIVE swipe deck right here —
                    // no browser bounce. Anything else keeps the Link fallback.
                    if let challengeId = InviteLink.challengeId(fromURL: sharedURL) {
                        Button {
                            inAppChallenge = ChallengeRef(id: challengeId)
                        } label: {
                            Label("Swipe it here", systemImage: "rectangle.stack.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.coral)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Link(destination: sharedURL) {
                            Label("Open shared invite", systemImage: "arrow.up.right.square")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.coral)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.coral.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                Text(Self.formatDmTime(msg.at))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            if !isMe { Spacer(minLength: 40) }
        }
    }

    private func load(silent: Bool = false) async {
        let fresh = await store.messages(for: threadId)
        if silent {
            // Merge by id so we don't flicker / lose optimistic local sends.
            var byId = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
            for m in fresh { byId[m.id] = m }
            messages = byId.values.sorted { $0.at < $1.at }
        } else {
            messages = fresh.sorted { $0.at < $1.at }
        }
    }

    private func send() async {
        guard let userId = authManager.userId else { return }
        let name = authManager.displayName ?? "You"
        let text = draft
        draft = ""
        if let msg = await store.sendMessage(threadId: threadId, userId: userId, name: name, text: text) {
            if !messages.contains(where: { $0.id == msg.id }) {
                messages.append(msg)
            }
        }
    }

    /// `at` is epoch milliseconds from the API / local store.
    static func formatDmTime(_ at: Double) -> String {
        let date = Date(timeIntervalSince1970: at > 1_000_000_000_000 ? at / 1000 : at)
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func firstURL(in text: String) -> URL? {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .compactMap(URL.init(string:))
            .first(where: { $0.scheme == "https" || $0.scheme == "http" })
    }
}
