import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var pushManager: PushManager
    @EnvironmentObject private var syncEngine: SyncEngine
    @ObservedObject private var thoughtfulness = ThoughtfulnessStore.shared
    @ObservedObject private var boards = SwipeListStore.shared
    @ObservedObject private var pools = PoolsStore.shared
    @State private var showSignIn = false
    @State private var visibility = "public"
    @State private var savingVisibility = false

    // The gifting persona — editable, local-first (server sync with the
    // public /people profile is an infra follow-up).
    @AppStorage("gifting_tagline") private var tagline = ""
    @AppStorage("gifting_philosophy") private var philosophy = ""
    @State private var editingTagline = false
    @State private var editingPhilosophy = false

    // Real recipient feedback: challenge/board responses (soft connections).
    @State private var connections: [SoftConnectionItem] = []
    @State private var signatureGift: SignatureGift?

    // "Signature gifts" = board items the user wrote a WHY for — curation by
    // thoughtfulness, not by volume.
    struct SignatureGift: Identifiable {
        let post: Post
        let why: String
        let forWhom: String?
        var id: String { post.id }
    }

    private var signatureGifts: [SignatureGift] {
        boards.lists.flatMap { list in
            list.posts.compactMap { post in
                guard let why = list.note(for: post.id) else { return nil }
                return SignatureGift(post: post, why: why, forWhom: list.recipientName)
            }
        }
        .prefix(6)
        .map { $0 }
    }

    // Boards still being curated — "what I'm searching for".
    private var openBoards: [SwipeList] {
        boards.lists.filter { $0.challengeId == nil }
    }

    private var giftsGiven: Int {
        boards.lists.filter { $0.challengeId != nil }.count + pools.pools.count
    }

    // Recipient satisfaction: aggregate yes-rate across everyone who swiped
    // a board/challenge this user sent. nil until real responses exist.
    private var satisfaction: Int? {
        let yes = connections.compactMap(\.yesCount).reduce(0, +)
        let total = connections.compactMap(\.totalSwipes).reduce(0, +)
        guard total >= 3 else { return nil }
        return Int((Double(yes) / Double(total) * 100).rounded())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // ── The public gifting persona ────────────────────────
                    // A curator profile, not a personal one: who you are AS A
                    // GIFTER. Finite by design — no infinite anything.
                    personaHeader

                    if !thoughtfulness.badges.isEmpty {
                        badgesRow
                    }

                    philosophyCard

                    if !signatureGifts.isEmpty {
                        signatureGiftsSection
                    }

                    if !openBoards.isEmpty {
                        searchingForSection
                    }

                    thankYousSection

                    // Your gifting life. (Group gifting + challenges AND events
                    // & reminders live in the Circles tab — dates belong with
                    // the people they're for. This screen is profile + shopping.)
                    VStack(spacing: 2) {
                        MoreSectionHeader(title: "Your gifting")

                        MoreRow(icon: "person.2.fill", title: "Friends", subtitle: "Discover, connect, message") {
                            FriendsView()
                        }

                        MoreRow(icon: "sparkles", title: "Edit taste", subtitle: "Maxi asks — sizes, vibes, dislikes") {
                            TasteInterviewView()
                        }

                        MoreRow(icon: "bag.fill", title: "Shop", subtitle: "Curated picks") {
                            ShopView()
                        }

                        MoreRow(icon: "leaf.fill", title: "Intentional Discover", subtitle: "A slower shelf, ranked by meaning") {
                            DiscoverView()
                        }
                    }

                    // Settings
                    VStack(spacing: 2) {
                        MoreSectionHeader(title: "Settings")

                        if authManager.isAuthenticated {
                            HStack(spacing: 12) {
                                Image(systemName: visibility == "private" ? "lock.fill" : "globe")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.coral)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Profile visibility")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Color.ink)
                                    Text(visibility == "private" ? "Only accepted friends can open your profile" : "Anyone can find your profile")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("Profile visibility", selection: $visibility) {
                                    Text("Public").tag("public")
                                    Text("Private").tag("private")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 154)
                                .disabled(savingVisibility)
                                .onChange(of: visibility) { _, value in
                                    Task { await saveVisibility(value) }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.surface)
                        }

                        Button(action: {
                            Task { await pushManager.requestPermission() }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.coral)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Push Notifications")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Color.ink)
                                    Text(pushManager.isRegistered ? "Enabled" : "Tap to enable")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if pushManager.isRegistered {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.surface)
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            Task {
                                await syncEngine.performFullSync(
                                    context: DataController.shared.mainContext,
                                    userId: authManager.userId
                                )
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.coral)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Sync Now")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Color.ink)
                                    if syncEngine.isSyncing {
                                        Text("Syncing...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if let lastSync = syncEngine.lastSyncDate {
                                        Text("Last: \(lastSync, style: .relative) ago")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if syncEngine.isSyncing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.surface)
                        }
                        .buttonStyle(.plain)
                    }

                    // Account
                    if authManager.isAuthenticated {
                        VStack(spacing: 2) {
                            MoreSectionHeader(title: "Account")

                            Button(action: {
                                DataController.shared.clearAllData()
                                authManager.signOut()
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.red)
                                        .frame(width: 28)

                                    Text("Sign Out")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.red)

                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color.surface)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Privacy
                    VStack(spacing: 2) {
                        MoreSectionHeader(title: "Legal")

                        MoreRow(icon: "hand.raised.fill", title: "Privacy Policy", subtitle: "Your data rights") {
                            PrivacyView()
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 14)
            }
            .background(Color.cream)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("You")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
            }
        }
        .sheet(isPresented: $showSignIn) {
            SignInView(showSignIn: $showSignIn)
                .environmentObject(authManager)
        }
        .sheet(isPresented: $editingTagline) {
            NoteEditorSheet(
                title: "Your tagline",
                prompt: "One line on your gifting style — e.g. “Making my friends cry happy tears since 2024”",
                text: tagline
            ) { tagline = String($0.prefix(80)) }
        }
        .sheet(isPresented: $editingPhilosophy) {
            NoteEditorSheet(
                title: "My gifting philosophy",
                prompt: "What matters to you when you give? e.g. “I choose gifts that tell a story.”",
                text: philosophy,
                long: true
            ) { philosophy = String($0.prefix(500)) }
        }
        .sheet(item: $signatureGift) { gift in
            SignatureGiftStorySheet(gift: gift)
        }
        .task {
            if let userId = authManager.userId {
                connections = (try? await APIClient.shared.fetchConnections(userId: userId)) ?? []
                if let profile = try? await APIClient.shared.fetchMe(userId: userId) {
                    visibility = profile.visibility == "private" ? "private" : "public"
                }
            }
        }
    }

    // ── Persona sections ──────────────────────────────────────────────────

    private var personaHeader: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(Color.gradient(for: .coral))
                .frame(width: 72, height: 72)
                .overlay {
                    Text(String(authManager.displayName?.prefix(1) ?? "🎁"))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }

            Text(authManager.displayName ?? "Giftmaxxer")
                .font(.displaySmall)
                .foregroundStyle(Color.ink)

            Button {
                editingTagline = true
            } label: {
                Text(tagline.isEmpty ? "Add a tagline — your gifting style in one line" : tagline)
                    .font(.system(size: 13))
                    .foregroundStyle(tagline.isEmpty ? .secondary : Color.ink)
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(.plain)

            if !authManager.isAuthenticated {
                Button("Sign in with Apple") { showSignIn = true }
                    .font(.labelBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.ink)
                    .clipShape(Capsule())
            }

            // Stats — the gifting record, not follower counts.
            HStack(spacing: 0) {
                statCell(value: "\(giftsGiven)", label: "gifts given")
                statDivider
                statCell(value: "\(thoughtfulness.points)", label: "Thoughtfulness Pts")
                statDivider
                statCell(value: satisfaction.map { "\($0)%" } ?? "—", label: "recipient 💛")
            }
            .padding(.vertical, 12)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.top, 12)
    }

    private var statDivider: some View {
        Rectangle().fill(Color.line).frame(width: 1, height: 28)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.coral)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var badgesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(thoughtfulness.badges) { badge in
                    HStack(spacing: 5) {
                        Image(systemName: badge.icon)
                            .font(.system(size: 11))
                        Text(badge.name)
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color.coral)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.coralSoft)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var philosophyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MoreSectionHeader(title: "My gifting philosophy")
                Button(philosophy.isEmpty ? "Write it" : "Edit") { editingPhilosophy = true }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.coral)
            }
            Text(philosophy.isEmpty
                 ? "What do you believe about giving? A sentence here tells people what kind of gifter you are."
                 : philosophy)
                .font(.system(size: 14))
                .foregroundStyle(philosophy.isEmpty ? .secondary : Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var signatureGiftsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MoreSectionHeader(title: "Signature gifts")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ForEach(signatureGifts) { gift in
                    Button {
                        signatureGift = gift
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            ZStack {
                                Color.gradient(for: gift.post.product.grad)
                                if let image = gift.post.product.image {
                                    CachedAsyncImage(url: image, width: 300)
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(gift.forWhom.map { "For \($0)" } ?? gift.why)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.ink)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Gifts you wrote a why for — tap one to read its story.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var searchingForSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MoreSectionHeader(title: "What I'm searching for")
            ForEach(openBoards.prefix(4)) { board in
                NavigationLink {
                    SwipeListDetailView(listId: board.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.coral)
                        Text("Looking for: \(board.name)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("\(board.posts.count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Post-gift feedback loop: what recipients said when they swiped what you
    // sent — the appreciation that closes the circle. (Thank-you videos with
    // recipient consent are the server-side follow-up; see CLOUD.md.)
    private var thankYousSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MoreSectionHeader(title: "Thank-yous & reactions")
            if connections.isEmpty {
                Text("When someone swipes a board or challenge you sent, their reaction lands here — the proof your gifts land.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                ForEach(connections.prefix(5)) { conn in
                    HStack(spacing: 10) {
                        AvatarView(name: conn.guestName, grad: .sage, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(conn.guestName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ink)
                            if let yes = conn.yesCount, let total = conn.totalSwipes, total > 0 {
                                Text("loved \(yes) of your \(total) picks")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let yes = conn.yesCount, let total = conn.totalSwipes,
                           total > 0, Double(yes) / Double(total) >= 0.5 {
                            Text("💛")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func saveVisibility(_ value: String) async {
        guard let userId = authManager.userId else { return }
        savingVisibility = true
        defer { savingVisibility = false }
        do {
            try await APIClient.shared.saveMeRaw(userId: userId, profile: ["visibility": value])
        } catch {
            // Restore the server value on the next profile refresh.
        }
    }
}

// Full story for a signature gift: the photo, who it was for, and the why.
struct SignatureGiftStorySheet: View {
    let gift: MoreView.SignatureGift
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ZStack {
                        Color.gradient(for: gift.post.product.grad)
                        if let image = gift.post.product.image {
                            CachedAsyncImage(url: image, width: 900)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    if let forWhom = gift.forWhom {
                        Label("For \(forWhom)", systemImage: "heart.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.coral)
                    }

                    Text(gift.post.product.name)
                        .font(.displaySmall)
                        .foregroundStyle(Color.ink)

                    Text("“\(gift.why)”")
                        .font(.system(size: 15))
                        .italic()
                        .foregroundStyle(Color.ink)

                    if let story = GiftStory.story(for: gift.post) {
                        Text(story)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .background(Color.surface)
            .toolbar {
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
        }
        .presentationDragIndicator(.visible)
    }
}

struct MoreSectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}

struct MoreRow<Destination: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.coral)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.surface)
        }
        .buttonStyle(.plain)
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.displayMedium)

                Text("Giftmaxxing respects your privacy. We collect only the data necessary to provide personalized gift recommendations.")
                    .font(.bodyLarge)

                Text("Data We Collect")
                    .font(.displaySmall)

                Text("Your interactions (likes, saves, swipes) help us understand your taste for gift recommendations. This data is stored securely on AWS and is never sold to third parties.")
                    .font(.bodyLarge)

                Text("Data Ownership")
                    .font(.displaySmall)

                Text("You own your data. You can request deletion of all your data at any time by contacting support or using the Sign Out option, which clears all local data.")
                    .font(.bodyLarge)

                Text("Amazon Affiliate Links")
                    .font(.displaySmall)

                Text("When you purchase products through our links, we may earn a small commission from Amazon Associates. This does not affect the price you pay.")
                    .font(.bodyLarge)
            }
            .padding(20)
        }
        .navigationTitle("Privacy")
    }
}
