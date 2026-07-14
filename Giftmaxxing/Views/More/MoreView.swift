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
    // Account deletion (App Store 5.1.1(v)) — a two-step confirm to prevent
    // accidents, then an irreversible server + local wipe.
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?

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

                            // Permanent account deletion (App Store 5.1.1(v)).
                            Button(action: { showDeleteConfirm = true }) {
                                HStack(spacing: 12) {
                                    if isDeleting {
                                        ProgressView().frame(width: 28)
                                    } else {
                                        Image(systemName: "trash")
                                            .font(.system(size: 16))
                                            .foregroundStyle(.red)
                                            .frame(width: 28)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(isDeleting ? "Deleting…" : "Delete Account")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.red)
                                        Text("Permanently erase your account and all data")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color.surface)
                            }
                            .buttonStyle(.plain)
                            .disabled(isDeleting)

                            if let deleteError {
                                Text(deleteError)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 4)
                            }
                        }
                    }

                    // Support & Legal
                    VStack(spacing: 2) {
                        MoreSectionHeader(title: "Support & Legal")

                        MoreRow(icon: "questionmark.circle.fill", title: "Help & Support", subtitle: "Contact us, FAQs") {
                            SupportView()
                        }

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
        .alert("Delete your account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("This permanently erases your account and all your data — profile, gift boards, pools, saved ideas, and connections. This cannot be undone.")
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

    // Irreversible: delete server-side data, then wipe every local store. On a
    // network failure we keep the user signed in so they can retry — never
    // report the account gone when the server rows survive.
    private func deleteAccount() async {
        guard !isDeleting else { return }
        isDeleting = true
        deleteError = nil
        // Capture the identity before signOut() nils it — wipeEverything needs
        // it to clear this account's per-identity onboarding flags.
        let identity = authManager.userId
        do {
            try await authManager.deleteAccount()   // server DELETE /account + signOut()
            // Hard local clean slate: taste, vectors, onboarding, gifting stores,
            // SwiftData — nothing about the old account survives on-device.
            AccountLocalState.wipeEverything(identity: identity)
        } catch {
            deleteError = "Couldn't delete your account. Check your connection and try again."
        }
        isDeleting = false
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

// In-app support surface (App Store 1.5): reachable from You → Help & Support.
// Contact + FAQ mirroring web/app/support/page.tsx, with a direct email and a
// link to the full support page.
struct SupportView: View {
    private let supportEmail = "adhsaksham27@gmail.com"
    private let supportURL = URL(string: "https://giftmaxxing-web.vercel.app/support")!

    private var mailtoURL: URL? {
        URL(string: "mailto:\(supportEmail)?subject=Giftmaxxing%20Support")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("We're here to help")
                    .font(.displayMedium)

                Text("Questions, feedback, or trouble with the app? Email us and we'll get back to you, usually within 1–2 business days.")
                    .font(.bodyLarge)
                    .foregroundStyle(Color.ink)

                if let mailtoURL {
                    Link(destination: mailtoURL) {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.fill")
                            Text(supportEmail).font(.labelBold)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(Color.coral)
                        .padding(14)
                        .background(Color.coralSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }

                Text("Frequently asked")
                    .font(.displaySmall)
                    .padding(.top, 4)

                faq(
                    "How do I delete my account?",
                    "Go to You → Account → Delete Account. After a confirmation step, your account and all associated data (profile, gift boards, pools, saved ideas, and connections) are permanently and immediately deleted. This can't be undone, and it needs no email or phone call. Signing out (without deleting) only clears data on this device."
                )
                faq(
                    "How is my data handled?",
                    "Your data lives in our own AWS account, encrypted at rest, and is never sold. Sensitive identifiers are redacted before any text reaches our AI provider. See the Privacy Policy for the full detail."
                )
                faq(
                    "Someone shared a swipe challenge with me — do I need an account?",
                    "No. You can swipe as a guest without signing up."
                )
                faq(
                    "How do group gifts and payments work?",
                    "Giftmaxxing helps you organize a group gift and invite people, but we don't process payments or hold funds — any money movement happens directly between you and the people you invite."
                )

                Link(destination: supportURL) {
                    HStack(spacing: 8) {
                        Image(systemName: "safari")
                        Text("Open the full support page").font(.labelBold)
                    }
                    .foregroundStyle(Color.coral)
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .background(Color.cream)
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func faq(_ q: String, _ a: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(q)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.ink)
            Text(a)
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
        }
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

                Text("You own your data. You can permanently delete your account and all associated data at any time — no email or phone call needed — from You → Account → Delete Account. Deletion is immediate and irreversible. Sign Out (without deleting) clears local data on this device but keeps your account.")
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
