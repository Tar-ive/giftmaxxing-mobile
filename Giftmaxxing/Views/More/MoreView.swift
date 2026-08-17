import AVKit
import PhotosUI
import SwiftUI
import SwiftData
import UIKit

struct MoreView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var pushManager: PushManager
    @EnvironmentObject private var syncEngine: SyncEngine
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var thoughtfulness = ThoughtfulnessStore.shared
    @ObservedObject private var boards = SwipeListStore.shared
    @ObservedObject private var invites = InviteAccess.shared
    @State private var showSignIn = false
    @State private var visibility = "public"
    @State private var savingVisibility = false
    // Account deletion (App Store 5.1.1(v)) — a two-step confirm to prevent
    // accidents, then an irreversible server + local wipe.
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var avatarSelection: PhotosPickerItem?
    @State private var avatarUrl: String?
    @State private var avatarError: String?
    @State private var isUploadingAvatar = false
    @State private var showSettings = false
    @State private var showEvents = false
    @ObservedObject private var appearance = AppearanceStore.shared
    // In-page tabbed navigation (Instagram-profile pattern): 0 = gift ideas
    // for {first name} + sizes, 1 = Gift Boards. (The posts grid left with
    // UGC — this app doesn't do posting.)
    @State private var activeTab = 0
    @Namespace private var tabUnderline
    // Board deep link from the post-save toast ("View").
    private struct BoardRef: Identifiable, Hashable { let id: String }
    @State private var presentedBoard: BoardRef?
    @State private var profileShowcase: [GiftShowcaseItem] = []
    @State private var profileSizes: [String: String] = [:]
    @State private var profileVibes: [String] = []
    @State private var profileDislikes: [String] = []
    @State private var profileGiftNote = ""
    @State private var friendCount = 0

    // The gifting persona — local-first, pushed to /me on every edit so the
    // public /people profile serves it to friends.
    @AppStorage("gifting_tagline") private var tagline = ""
    @AppStorage("gifting_philosophy") private var philosophy = ""
    // Fingerprint of the last showcase synced to the server, to skip no-op PUTs.
    @AppStorage("gifting_showcase_synced") private var showcaseSynced = ""
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
                    personaHeader

                    // Instagram-profile-style contextual sub-navigation: one
                    // icon strip, three content panels swapped in place.
                    profileTabStrip
                    switch activeTab {
                    case 0:
                        ownerGiftListSection
                        ownerSizesSection
                    default:
                        boardsPanel
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 14)
            }
            .background(Color.cream)
            .navigationDestination(item: $presentedBoard) { ref in
                SwipeListDetailView(listId: ref.id)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("You")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(Color.ink)
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .alert("Delete your account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) { Task { await deleteAccount() } }
        } message: {
            Text("This permanently erases your account and all your data — profile, gift boards, pools, saved ideas, and connections. This cannot be undone.")
        }
        .alert("Couldn’t update photo", isPresented: Binding(
            get: { avatarError != nil },
            set: { if !$0 { avatarError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(avatarError ?? "Please try another photo.")
        }
        .sheet(isPresented: $showSignIn) {
            SignInView(showSignIn: $showSignIn)
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(isPresented: $editingTagline) {
            NoteEditorSheet(
                title: "Your tagline",
                prompt: "One line on your gifting style — e.g. “Making my friends cry happy tears since 2024”",
                text: tagline
            ) {
                tagline = String($0.prefix(80))
                Task { await pushPersona() }
            }
        }
        .sheet(isPresented: $editingPhilosophy) {
            NoteEditorSheet(
                title: "My gifting philosophy",
                prompt: "What matters to you when you give? e.g. “I choose gifts that tell a story.”",
                text: philosophy,
                long: true
            ) {
                philosophy = String($0.prefix(500))
                Task { await pushPersona() }
            }
        }
        .sheet(item: $signatureGift) { gift in
            SignatureGiftStorySheet(gift: gift)
        }
        .onChange(of: avatarSelection) { _, item in
            guard let item else { return }
            Task { await uploadAvatar(item) }
        }
        .onAppear { consumePendingBoardRoute() }
        .onChange(of: appState.pendingBoardId) { _, _ in consumePendingBoardRoute() }
        .onChange(of: appState.pendingBoardsHome) { _, _ in consumePendingBoardRoute() }
        .task(id: authManager.userId) {
            if let userId = authManager.userId {
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "profilePreview") {
                    tagline = "Thoughtful gifts, zero guesswork."
                    profileSizes = ["shirt": "M", "shoes": "8.5", "pants": "28"]
                    profileVibes = ["foodie", "luxury", "thoughtful"]
                    profileDislikes = ["candles"]
                    profileGiftNote = "I love thoughtful gifts"
                    profileShowcase = previewShowcase
                    if let profile = try? await APIClient.shared.fetchPerson(userId: userId) {
                        avatarUrl = profile.imageUrl
                        tagline = profile.tagline ?? tagline
                        if let showcase = profile.giftShowcase, !showcase.isEmpty { profileShowcase = showcase }
                        profileSizes = profile.clothingSizes ?? profileSizes
                        profileVibes = profile.interests ?? profileVibes
                        profileDislikes = profile.dislikes ?? profileDislikes
                        profileGiftNote = profile.giftNote ?? profileGiftNote
                    }
                    return
                }
                #endif
                connections = (try? await APIClient.shared.fetchConnections(userId: userId)) ?? []
                friendCount = (try? await APIClient.shared.listFriends(userId: userId, status: "accepted").count) ?? 0
                if let profile = try? await APIClient.shared.fetchMe(userId: userId) {
                    visibility = profile.visibility == "private" ? "private" : "public"
                    avatarUrl = profile.imageUrl
                    // Adopt server persona on a fresh install; local edits win
                    // otherwise (they're pushed on every save).
                    if tagline.isEmpty, let t = profile.tagline { tagline = t }
                    if philosophy.isEmpty, let p = profile.philosophy { philosophy = p }
                    profileShowcase = profile.giftShowcase ?? []
                    profileSizes = profile.clothingSizes ?? PersonalizationStore.clothingSizes ?? [:]
                    profileVibes = profile.interests ?? PersonalizationStore.consultVibes
                    profileDislikes = profile.dislikes ?? PersonalizationStore.dislikes
                    profileGiftNote = profile.giftNote ?? PersonalizationStore.giftNote ?? ""
                }
                await syncShowcase(userId: userId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .consultProfileUpdated)) { _ in
            loadLocalTaste()
        }
    }

    // ── Persona → server sync ─────────────────────────────────────────────

    private func pushPersona() async {
        guard let userId = authManager.userId else { return }
        try? await APIClient.shared.saveMeRaw(userId: userId, profile: [
            "tagline": tagline,
            "philosophy": philosophy,
        ])
    }

    // The profile's "gifts I'd love" photos: recently liked/saved feed finds
    // first, then signature gifts (why-noted board items) to fill. Synced to
    // /me so friends see them on the public profile.
    private func syncShowcase(userId: String) async {
        var items: [[String: Any]] = []
        var seen = Set<String>()
        var descriptor = FetchDescriptor<CachedPost>(
            predicate: #Predicate { $0.liked || $0.saved },
            sortBy: [SortDescriptor(\.cachedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 6
        for cached in (try? modelContext.fetch(descriptor)) ?? [] where seen.insert(cached.postId).inserted {
            var item: [String: Any] = ["postId": cached.postId, "name": cached.productName]
            if let image = cached.productImage { item["imageUrl"] = image }
            if !cached.productBrand.isEmpty { item["brand"] = cached.productBrand }
            if cached.productPrice > 0 { item["price"] = cached.productPrice }
            if let url = cached.productUrl { item["productUrl"] = url }
            items.append(item)
        }
        for gift in signatureGifts where items.count < 6 && seen.insert(gift.post.id).inserted {
            var item: [String: Any] = ["postId": gift.post.id, "name": gift.post.product.name, "why": gift.why]
            if let image = gift.post.product.image { item["imageUrl"] = image }
            item["brand"] = gift.post.product.brand
            item["price"] = gift.post.product.price
            if let url = gift.post.productUrl ?? gift.post.url { item["productUrl"] = url }
            items.append(item)
        }
        let fingerprint = items.compactMap { $0["postId"] as? String }.joined(separator: ",")
        guard fingerprint != showcaseSynced else { return }
        do {
            try await APIClient.shared.saveMeRaw(userId: userId, profile: ["giftShowcase": items])
            showcaseSynced = fingerprint
        } catch {}
    }

    // ── Persona sections ──────────────────────────────────────────────────

    private var personaHeader: some View {
        let displayName = authManager.displayName ?? "Giftmaxxer"
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                PhotosPicker(selection: $avatarSelection, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(name: displayName, grad: .coral, size: 92, imageUrl: avatarUrl, anonymousFallback: true)
                        if isUploadingAvatar {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.ink.opacity(0.72))
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.coral)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.cream, lineWidth: 3))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isUploadingAvatar || !authManager.isAuthenticated)
                .accessibilityLabel(avatarUrl == nil ? "Add profile photo" : "Change profile photo")

                VStack(alignment: .leading, spacing: 5) {
                    Text(displayName)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ink)
                    Text("@\(profileHandle(displayName))")
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSecondary)
                    Button { editingTagline = true } label: {
                        Text(tagline.isEmpty ? "Add your gifting tagline" : tagline)
                            .font(.system(size: 13))
                            .foregroundStyle(tagline.isEmpty ? Color.coral : Color.ink)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    Label("\(friendCount) \(friendCount == 1 ? "friend" : "friends")", systemImage: "person.2.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.coral)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.coralSoft)
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
            }

            if !authManager.isAuthenticated {
                Button("Sign in with Apple") { showSignIn = true }
                    .font(.labelBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.ink)
                    .clipShape(Capsule())
            }

        }
        .padding(.top, 12)
    }

    // First name for the personalized wishlist title — "Gift ideas for Saksham".
    private var firstName: String {
        guard let name = authManager.displayName?
            .split(separator: " ").first.map(String.init),
            !name.isEmpty
        else { return "me" }
        return name
    }

    // The Instagram-style icon strip: three sub-views of the same profile,
    // switched in place (activeTab) instead of stacked down the page.
    private var profileTabStrip: some View {
        HStack(spacing: 0) {
            profileTab(index: 0, icon: "gift", label: "Gift ideas for \(firstName)")
            profileTab(index: 1, icon: "rectangle.stack", label: "Gift Boards")
        }
        .sensoryFeedback(.selection, trigger: activeTab)
    }

    private func profileTab(index: Int, icon: String, label: String) -> some View {
        let isActive = activeTab == index
        return Button {
            withAnimation(.snappy) { activeTab = index }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: isActive ? "\(icon).fill" : icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isActive ? Color.ink : Color.inkTertiary)
                    .contentTransition(.symbolEffect(.replace))
                ZStack {
                    Color.clear.frame(height: 2)
                    if isActive {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Color.ink)
                            .frame(width: 56, height: 2)
                            .matchedGeometryEffect(id: "profileTabUnderline", in: tabUnderline)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // Gift Boards live HERE now (removed from the Home rail) — reuse the full
    // boards home (create, add by link, rows into detail).
    private var boardsPanel: some View {
        SwipeListsHomeView(horizontalPadding: 0)
    }

    // Post-save toast "View" landed us here — show the Boards tab and, for a
    // specific board, push its detail.
    private func consumePendingBoardRoute() {
        if let boardId = appState.pendingBoardId {
            activeTab = 1
            presentedBoard = BoardRef(id: boardId)
            appState.pendingBoardId = nil
            appState.pendingBoardsHome = false
        } else if appState.pendingBoardsHome {
            activeTab = 1
            appState.pendingBoardsHome = false
        }
    }

    private var ownerGiftListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MoreSectionHeader(title: "Gift ideas for \(firstName)")
                Spacer()
                if let list = boards.myGiftIdeas {
                    NavigationLink("See all") { SwipeListDetailView(listId: list.id) }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.coral)
                }
            }
            if boards.myGiftIdeas?.posts.isEmpty != false {
                Button { appState.selectedTab = .swipe } label: {
                    Label("Swipe right on gifts you’d love", systemImage: "hand.draw.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    ForEach((boards.myGiftIdeas?.posts ?? []).prefix(2)) { post in
                        giftListCard(GiftShowcaseItem(
                            postId: post.id,
                            name: post.product.name,
                            imageUrl: post.product.image,
                            brand: post.product.brand,
                            price: post.product.price,
                            productUrl: post.productUrl ?? post.url
                        ))
                    }
                }
            }
        }
    }

    @ViewBuilder private var ownerSizesSection: some View {
        if !profileSizes.isEmpty {
            VStack(alignment: .leading, spacing: ThemeSpacing.sm) {
                MoreSectionHeader(title: "My sizes")
                measurementsRow(profileSizes)
            }
        }
    }

    private func giftListCard(_ item: GiftShowcaseItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                Color.surfaceSunken
                if let image = item.imageUrl { CachedAsyncImage(url: image, width: 360) }
                else { Image(systemName: "gift.fill").foregroundStyle(Color.coral) }
            }
            .frame(height: 118)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(item.name ?? "Gift idea")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
            HStack {
                Text(item.brand ?? "Saved find").lineLimit(1)
                Spacer()
                if let price = item.price, price > 0 { Text(price, format: .currency(code: "USD")) }
            }
            .font(.caption)
            .foregroundStyle(Color.inkSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
    }

    private var ownerTasteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MoreSectionHeader(title: "My taste")
                Spacer()
                NavigationLink("Edit") { TasteInterviewView() }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.coral)
            }
            if !profileSizes.isEmpty { measurementsRow(profileSizes) }
            if !profileVibes.isEmpty {
                profileCard(title: "Gift vibes") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(profileVibes.prefix(6), id: \.self) { vibe in
                                Text(vibe)
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Color.coralSoft)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            if !profileGiftNote.isEmpty || !profileDislikes.isEmpty {
                profileCard(title: "Good to know") {
                    if !profileGiftNote.isEmpty { Text(profileGiftNote).foregroundStyle(Color.ink) }
                    if !profileDislikes.isEmpty {
                        Label("Avoid \(profileDislikes.joined(separator: ", "))", systemImage: "hand.raised.fill")
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
            }
        }
    }

    private func measurementsRow(_ sizes: [String: String]) -> some View {
        profileCard(title: "Measurements") {
            HStack(spacing: 0) {
                ForEach(orderedSizes(sizes), id: \.0) { key, value in
                    VStack(spacing: 5) {
                        Image(systemName: sizeIcon(key))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.coral)
                        Text(value).font(.system(size: 17, weight: .bold, design: .rounded))
                        Text(key.capitalized).font(.caption).foregroundStyle(Color.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func profileCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(Color.ink)
            content().font(.system(size: 13))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        isUploadingAvatar = true
        defer {
            isUploadingAvatar = false
            avatarSelection = nil
        }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self),
                  let source = UIImage(data: raw) else { throw AvatarUploadError.unreadable }
            let maxSide: CGFloat = 1600
            let scale = min(1, maxSide / max(source.size.width, source.size.height))
            let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                source.draw(in: CGRect(origin: .zero, size: size))
            }
            guard let data = image.jpegData(compressionQuality: 0.88) else { throw AvatarUploadError.unreadable }
            let upload = try await APIClient.shared.createAvatarUpload(mimeType: "image/jpeg", fileSize: data.count)
            try await APIClient.shared.uploadAvatar(data: data, to: upload.uploadUrl, headers: upload.uploadHeaders)
            avatarUrl = try await APIClient.shared.completeAvatarUpload(avatarId: upload.avatarId)
        } catch {
            avatarError = error.localizedDescription
        }
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
                 ? "What do you believe about giving?"
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
                Text("Reactions to boards you send land here.")
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
                            Image(systemName: "heart.fill").foregroundStyle(Color.coral)
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

    private var settingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 2) {
                        MoreSectionHeader(title: "Profile")
                        MoreRow(icon: "sparkles", title: "Edit taste", subtitle: "Sizes, vibes, dislikes") { TasteInterviewView() }
                        // Friends/DMs are part of the invite-only social layer.
                        if invites.isUnlocked {
                            MoreRow(icon: "person.2.fill", title: "Friends", subtitle: "Discover, connect, message") { FriendsView() }
                        }
                    }
                    VStack(spacing: 2) {
                        MoreSectionHeader(title: "Explore")
                        MoreRow(icon: "bag.fill", title: "Shop", subtitle: "Curated picks") { ShopView() }
                        MoreRow(icon: "leaf.fill", title: "Intentional Discover", subtitle: "Ranked by meaning") { DiscoverView() }
                        MoreRow(icon: "paintpalette", title: "Appearance", subtitle: "Try a different theme") { AppearanceView() }
                        // Birthdays and occasions used to live on the Circles
                        // tab; they're personal planning, not a social feature,
                        // so they stay reachable without an invite.
                        settingsButton(
                            icon: "calendar",
                            title: "Gift calendar",
                            subtitle: "Birthdays, anniversaries, reminders"
                        ) { showEvents = true }
                        // The only door into the social half of the app.
                        if invites.isUnlocked {
                            settingsButton(
                                icon: "person.3.fill",
                                title: "Circles",
                                subtitle: "Unlocked — find it in the tab bar"
                            ) {
                                showSettings = false
                                appState.selectedTab = .circles
                            }
                        } else {
                            settingsButton(
                                icon: "lock.fill",
                                title: "Circles",
                                subtitle: "Invite-only: shared calendars, pools, group gifts"
                            ) {
                                showSettings = false
                                // Let the settings sheet finish dismissing —
                                // two sheet transitions in the same runloop
                                // tick swallow the second presentation.
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(350))
                                    appState.showInviteCode = true
                                }
                            }
                        }
                        // Operator-only. The row itself is absent for everyone
                        // else — a disabled or hidden-behind-a-tap entry would
                        // still tell people the bench exists.
                        if DebugSessionManager.shared.isUnlocked {
                            MoreRow(icon: "slider.horizontal.3", title: "Design bench", subtitle: "Feed variants A / B / C") { DebugMenuView() }
                        }
                    }
                    VStack(spacing: 2) {
                        MoreSectionHeader(title: "Settings")
                        HStack(spacing: 12) {
                            Image(systemName: appearance.mode.icon)
                                .foregroundStyle(Color.coral).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Appearance").font(.system(size: 15, weight: .medium))
                                Text(appearance.mode.label)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("Appearance", selection: $appearance.mode) {
                                ForEach(AppearanceMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 190)
                        }
                        .padding(14)
                        .background(Color.surface)
                        if authManager.isAuthenticated {
                            HStack(spacing: 12) {
                                Image(systemName: visibility == "private" ? "lock.fill" : "globe")
                                    .foregroundStyle(Color.coral).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Profile visibility").font(.system(size: 15, weight: .medium))
                                    Text(visibility == "private" ? "Friends only" : "Anyone can view")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Picker("Profile visibility", selection: $visibility) {
                                    Text("Public").tag("public")
                                    Text("Private").tag("private")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 142)
                                .disabled(savingVisibility)
                                .onChange(of: visibility) { _, value in Task { await saveVisibility(value) } }
                            }
                            .padding(14)
                            .background(Color.surface)
                        }
                        settingsButton(
                            icon: "bell.fill",
                            title: "Push Notifications",
                            subtitle: pushManager.isRegistered ? "Enabled" : "Tap to enable"
                        ) { Task { await pushManager.requestPermission() } }
                        settingsButton(
                            icon: "arrow.triangle.2.circlepath",
                            title: syncEngine.isSyncing ? "Syncing…" : "Sync Now",
                            subtitle: syncEngine.lastSyncDate.map { "Last synced \($0.formatted(.relative(presentation: .named)))" }
                        ) {
                            Task {
                                await syncEngine.performFullSync(
                                    context: DataController.shared.mainContext,
                                    userId: authManager.userId
                                )
                            }
                        }
                    }
                    if authManager.isAuthenticated {
                        VStack(spacing: 2) {
                            MoreSectionHeader(title: "Account")
                            settingsButton(icon: "rectangle.portrait.and.arrow.right", title: "Sign Out", role: .destructive) {
                                DataController.shared.clearAllData()
                                authManager.signOut()
                            }
                            settingsButton(icon: "trash", title: "Delete Account", subtitle: "Permanently erase your account and all data", role: .destructive) {
                                showDeleteConfirm = true
                            }
                        }
                    }
                    VStack(spacing: 2) {
                        MoreSectionHeader(title: "Support & Legal")
                        settingsButton(
                            icon: "map.fill",
                            title: "Replay app tour",
                            subtitle: "Where boards, dates, and search live"
                        ) {
                            showSettings = false
                            // Let the sheet dismiss before the overlay appears.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                NotificationCenter.default.post(name: .replayCoachMarks, object: nil)
                            }
                        }
                        MoreRow(icon: "questionmark.circle.fill", title: "Help & Support", subtitle: "Contact us, FAQs") { SupportView() }
                        MoreRow(icon: "hand.raised.fill", title: "Privacy Policy", subtitle: "Your data rights") { PrivacyView() }
                    }
                    buildStamp
                }
                .padding(14)
            }
            .background(Color.cream)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } }
            }
            // EventsView owns a NavigationStack, so it presents rather than
            // pushes (no nested-stack double toolbar).
            .sheet(isPresented: $showEvents) {
                EventsView()
                    .environmentObject(appState)
            }
        }
    }

    // Version, build, and the commit that produced this binary — so a bug
    // report names the exact code the tester ran.
    private var buildStamp: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let commit = info?["GitCommit"] as? String ?? "unknown"
        return Text("Giftmaxxing \(version) (\(build)) · \(commit)")
            .font(.caption2)
            .foregroundStyle(Color.inkTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .textSelection(.enabled)
    }

    private func settingsButton(
        icon: String,
        title: String,
        subtitle: String? = nil,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium))
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .foregroundStyle(role == .destructive ? Color.red : Color.ink)
            .padding(14)
            .background(Color.surface)
        }
        .buttonStyle(.plain)
    }

    private func loadLocalTaste() {
        profileSizes = PersonalizationStore.clothingSizes ?? [:]
        profileVibes = PersonalizationStore.consultVibes
        profileDislikes = PersonalizationStore.dislikes
        profileGiftNote = PersonalizationStore.giftNote ?? ""
    }

    private func profileHandle(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(22).description
    }

    private var previewShowcase: [GiftShowcaseItem] {
        [
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

    private func orderedSizes(_ sizes: [String: String]) -> [(String, String)] {
        let order = ["shirt", "shoes", "pants", "dress", "ring"]
        return sizes.sorted {
            (order.firstIndex(of: $0.key.lowercased()) ?? 99) < (order.firstIndex(of: $1.key.lowercased()) ?? 99)
        }
        .prefix(3)
        .map { ($0.key, $0.value) }
    }

    private func sizeIcon(_ key: String) -> String {
        switch key.lowercased() {
        case "shirt": "tshirt.fill"
        case "shoes", "shoe": "shoe.2.fill"
        default: "ruler.fill"
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

private enum AvatarUploadError: LocalizedError {
    case unreadable

    var errorDescription: String? { "That photo couldn’t be prepared. Please choose another one." }
}

struct UGCProfilePostSheet: View {
    let post: UGCPost
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var giftIdeas = SwipeListStore.shared
    @EnvironmentObject private var appState: AppState
    @State private var liked = false
    @State private var likeCount = 0
    @State private var comments: [Comment] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var galleryIndex = 0
    @State private var measuredAspect: CGFloat?
    @ObservedObject private var musicPlayback = UGCFeedMusicPlayback.shared

    private var gallery: [String] {
        let values = post.mediaUrls ?? []
        if !values.isEmpty { return values }
        return [post.mediaUrl].compactMap { $0 }
    }

    private var giftPost: Post {
        Post(
            id: post.id,
            user: post.authorName ?? "Giftmaxxer",
            authorImageUrl: post.authorImageUrl,
            time: "",
            product: Product(
                id: post.id,
                name: post.caption,
                brand: post.authorName ?? "Giftmaxxing",
                price: 0,
                grad: .coral,
                emoji: "🎁",
                image: post.posterUrl ?? gallery.first,
                images: gallery
            ),
            caption: post.caption,
            likes: likeCount,
            liked: liked,
            comments: comments,
            commentCount: post.comments,
            source: "ugc",
            contentType: post.mediaType == "video"
                ? "ugc_video"
                : (gallery.count > 1 ? "ugc_carousel" : "ugc_image"),
            mediaUrl: post.mediaUrl,
            posterUrl: post.posterUrl,
            music: post.music
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    media
                        .frame(maxWidth: .infinity)
                        .aspectRatio(sheetAspectRatio, contentMode: .fit)
                        .overlay(alignment: .bottom) {
                            // Same "Find similar" affordance as the feed card —
                            // this sheet had neither it nor the shop rail.
                            Button {
                                // The slide on screen, not slide 1 — paging the
                                // carousel then tapping this used to search the
                                // first image regardless.
                                let image = gallery.indices.contains(galleryIndex)
                                    ? gallery[galleryIndex]
                                    : (gallery.first ?? post.posterUrl)
                                Task { await VisualSearchLauncher.open(imageUrl: image, in: appState) }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkle.magnifyingglass")
                                    Text("Find similar")
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(.black.opacity(0.55), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 12)
                            .accessibilityLabel("Find similar products in this photo")
                        }

                    ShopThisPostRail(
                        postId: post.postId,
                        imageUrl: gallery.first ?? post.posterUrl,
                        caption: post.caption
                    )
                        .background(Color.surfaceSunken)
                        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let music = post.music, post.mediaType != "video" {
                                musicPlayback.toggle(postId: post.id, track: music)
                            }
                        }
                    Text(post.caption)
                        .font(.body)
                        .foregroundStyle(Color.ink)
                    if let music = post.music {
                        Button {
                            musicPlayback.toggle(postId: post.id, track: music)
                        } label: {
                            Label(
                                "\(music.title) · \(music.artist)",
                                systemImage: isPlayingMusic ? "pause.fill" : "music.note"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.ink)
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 20) {
                        Button { Task { await toggleLike() } } label: {
                            Label("\(likeCount)", systemImage: liked ? "heart.fill" : "heart")
                                .foregroundStyle(liked ? Color.coral : Color.ink)
                        }
                        Label("\(comments.count)", systemImage: "bubble.left")
                        if let value = post.mediaUrl ?? post.posterUrl, let url = URL(string: value) {
                            ShareLink(item: url, subject: Text("Gift find"), message: Text("Found this on Giftmaxxing")) {
                                Image(systemName: "paperplane")
                            }
                        }
                        Button { giftIdeas.toggleMyGiftIdea(giftPost) } label: {
                            Image(systemName: giftIdeas.containsInMyGiftIdeas(giftPost) ? "bookmark.fill" : "bookmark")
                                .foregroundStyle(giftIdeas.containsInMyGiftIdeas(giftPost) ? Color.coral : Color.ink)
                        }
                        Spacer()
                    }
                    .font(.system(size: 17, weight: .semibold))

                    if !comments.isEmpty {
                        ForEach(comments) { comment in
                            HStack(alignment: .top, spacing: 8) {
                                AvatarView(
                                    name: comment.user,
                                    grad: .peach,
                                    size: 28,
                                    imageUrl: comment.authorImageUrl,
                                    anonymousFallback: true
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(comment.user).font(.caption.weight(.bold))
                                    Text(comment.text).font(.subheadline)
                                }
                                Spacer()
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("Add a comment…", text: $draft, axis: .vertical)
                            .lineLimit(1...3)
                            .padding(10)
                            .background(Color.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Button { Task { await sendComment() } } label: {
                            if sending { ProgressView() }
                            else { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        }
                        .tint(Color.coral)
                        .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(14)
            }
            .background(Color.cream)
            .navigationTitle("Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                likeCount = post.likes ?? 0
                if let states = try? await APIClient.shared.fetchPostLikeStates(postIds: [post.id]) {
                    liked = states.contains(post.id)
                }
                comments = (try? await APIClient.shared.fetchPostComments(postId: post.id).items) ?? []
                if let music = post.music {
                    musicPlayback.play(postId: post.id, track: music)
                }
            }
            .onDisappear { musicPlayback.stop(postId: post.id) }
        }
    }

    private func toggleLike() async {
        liked.toggle()
        likeCount = max(0, likeCount + (liked ? 1 : -1))
        if let response = try? await APIClient.shared.setPostLike(postId: post.id, liked: liked) {
            liked = response.liked
            likeCount = response.likes
        }
    }

    private func sendComment() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        if let response = try? await APIClient.shared.addPostComment(postId: post.id, text: text) {
            comments.append(response.item)
            draft = ""
        }
    }

    // Posts open at their real shape here too — this sheet forced 1:1, so a
    // tall photo was cropped to a square while the feed showed it full.
    private var sheetAspectRatio: CGFloat {
        if post.mediaType == "video" { return MediaAspect.vertical }
        return measuredAspect.map(MediaAspect.snap) ?? MediaAspect.square
    }

    @ViewBuilder private var media: some View {
        if post.mediaType == "video", let value = post.mediaUrl, let url = URL(string: value) {
            VideoPlayer(player: AVPlayer(url: url))
        } else if gallery.count > 1 {
            ZStack(alignment: .topTrailing) {
                TabView(selection: $galleryIndex) {
                    ForEach(Array(gallery.enumerated()), id: \.offset) { index, image in
                        CachedAsyncImage(url: image, width: 900) { ratio in
                            if index == 0, measuredAspect == nil { measuredAspect = ratio }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                Text("\(galleryIndex + 1)/\(gallery.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, ThemeSpacing.sm)
                    .padding(.vertical, ThemeSpacing.xs)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(ThemeSpacing.sm)
            }
        } else if let image = gallery.first ?? post.posterUrl {
            CachedAsyncImage(url: image, width: 900) { ratio in
                if measuredAspect == nil { measuredAspect = ratio }
            }
        } else {
            Image(systemName: post.mediaType == "video" ? "video.fill" : "photo.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.inkTertiary)
        }
    }

    private var isPlayingMusic: Bool {
        musicPlayback.activePostId == post.id && musicPlayback.isPlaying
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
