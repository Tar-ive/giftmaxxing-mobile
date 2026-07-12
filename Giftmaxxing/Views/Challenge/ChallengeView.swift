import SwiftUI

// Swipe-challenge sharing, in-app. Mirrors the web's /challenge page and its
// Instagram-style guest boundary:
//   • ANYONE (signed in or not) can create + share a challenge — the link opens
//     in the recipient's mobile BROWSER where they swipe as a guest, no
//     account, no install (that's the viral loop).
//   • Seeing the responses is the HARD boundary: it requires a signed-in
//     account. Signed-out senders still collect responses under the device's
//     anonymous id; they're claimed onto the account on sign-in (same claim
//     flow as the web).
struct ChallengeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    // Optional image seed (share-extension / visual-search captures): the
    // server embeds it and builds the deck around it — "would they like THIS?"
    var seedImage: UIImage? = nil

    // Sheet presentations set this so there's an explicit way OUT — without it
    // a modally-presented challenge had no visible exit (swipe-down only).
    var showsClose = false

    /// Prefill "who is this for?" when launched from Friends / DM / Circles.
    var prefillTheirName: String = ""
    /// When launched from a DM, the created challenge is also posted there.
    var dmThreadId: String? = nil

    @State private var yourName = ""
    @State private var theirName = ""
    @State private var occasion = "birthday"
    @State private var includeDate = false
    @State private var date = Date()

    // Deck theme: seeding with ONE concrete gift keeps the whole deck coherent
    // (the server packs it with twins + same-vibe items), so their swipes
    // answer "would they like THIS kind of thing?" — colors, style and all.
    @ObservedObject private var swipeList = SwipeListStore.shared
    @State private var seedPostId: String?

    // Server-side challenge: deck + verdicts live in the backend; the link
    // just carries the challengeId. nil until created; invalidated on edits.
    @State private var challengeId: String?
    @State private var isCreating = false
    @State private var serverUnavailable = false
    @State private var postedChallengeIdToDm: String?

    private static let occasions: [(id: String, label: String, emoji: String)] = [
        ("birthday", "Birthday", "🎂"),
        ("anniversary", "Anniversary", "💝"),
        ("wedding", "Wedding", "💒"),
        ("valentines", "Valentine's Day", "🌹"),
        ("mothers-day", "Mother's Day", "🌷"),
        ("fathers-day", "Father's Day", "🧔"),
        ("graduation", "Graduation", "🎓"),
        ("housewarming", "Housewarming", "🏡"),
        ("holiday", "Holiday / Christmas", "🎄"),
        ("baby-shower", "Baby shower", "🍼"),
        ("other", "Other occasion", "✨"),
    ]

    private var senderId: String {
        authManager.userId ?? InteractionQueue.anonymousUserId
    }

    private var dateString: String? {
        guard includeDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private var inviterName: String {
        yourName.isEmpty ? (authManager.displayName ?? "A friend") : yourName
    }

    private var inviteURL: URL? {
        InviteLink.buildURL(
            inviterName: inviterName,
            senderId: senderId,
            to: theirName,
            occasion: occasion == "other" ? nil : occasion,
            date: dateString,
            challengeId: challengeId
        )
    }

    // POST /challenges — seed priority: captured image (embedded server-side),
    // else the sender's recent taste keys (centroid deck). No seed or no
    // network → legacy local-deck link so sharing never blocks.
    private func createServerChallenge() async {
        guard !isCreating else { return }
        isCreating = true
        defer { isCreating = false }

        var imageBase64: String?
        if let seedImage {
            imageBase64 = seedImage.resized(maxDimension: 512)
                .jpegData(compressionQuality: 0.8)?
                .base64EncodedString()
        }
        // Seed priority: chosen gift > captured photo > taste-key centroid.
        var seedKeys: [String] = []
        if imageBase64 == nil && seedPostId == nil {
            seedKeys = await TasteProfileStore.shared.snapshot().seedKeys
        }
        guard imageBase64 != nil || seedPostId != nil || !seedKeys.isEmpty else {
            serverUnavailable = true
            return
        }

        do {
            let response = try await APIClient.shared.createChallenge(
                senderId: senderId,
                seedImageBase64: seedPostId == nil ? imageBase64 : nil,
                seedPostId: seedPostId,
                seedKeys: seedKeys.isEmpty ? nil : seedKeys,
                inviterName: inviterName,
                to: theirName,
                occasion: occasion == "other" ? nil : occasion,
                date: dateString
            )
            challengeId = response.challengeId
            serverUnavailable = false
            await postChallengeToDmIfNeeded()
            AnalyticsEngine.shared.trackScreenView(screen: "challenge_created_server")
        } catch {
            serverUnavailable = true
        }
    }

    private func postChallengeToDmIfNeeded() async {
        guard let challengeId,
              postedChallengeIdToDm != challengeId,
              let dmThreadId,
              let userId = authManager.userId,
              let url = inviteURL else { return }

        let name = authManager.displayName ?? "You"
        let text = "I made you a gift challenge — swipe a few finds so I can get your gift right 🎁\n\(url.absoluteString)"
        if await FriendsStore.shared.sendMessage(
            threadId: dmThreadId,
            userId: userId,
            name: name,
            text: text
        ) != nil {
            postedChallengeIdToDm = challengeId
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero
                VStack(alignment: .leading, spacing: 6) {
                    Text("Find their exact gift taste — without asking")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.ink)
                    Text("Share a 60-second swipe challenge. They swipe in their browser — no app, no sign-up — and their taste lands right here.")
                        .font(.bodyMedium)
                        .foregroundStyle(.secondary)
                }

                // Image-seeded challenge — the deck is built around this capture.
                if let seedImage {
                    HStack(spacing: 12) {
                        Image(uiImage: seedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Seeded with your photo")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.ink)
                            Text("Their deck is built around this — their swipes tell you if they'd love it, without ever showing your hand.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.coralSoft.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                // Theme picker — a saved gift idea anchors the deck.
                if seedImage == nil && !swipeList.posts.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("BUILD THE DECK AROUND A GIFT IDEA")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text("Pick one of your saved finds — their deck fills with it and lookalikes, so their swipes tell you if the style and colors land.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(swipeList.posts) { post in
                                    SeedPickCard(
                                        post: post,
                                        isSelected: seedPostId == post.id
                                    ) {
                                        seedPostId = seedPostId == post.id ? nil : post.id
                                        challengeId = nil
                                    }
                                }
                            }
                        }
                        if seedPostId == nil {
                            Text("Nothing picked — the deck falls back to your overall taste.")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(16)
                    .background(Color.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                // Personalize card
                VStack(alignment: .leading, spacing: 14) {
                    Text("PERSONALIZE YOUR CHALLENGE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)

                    TextField("Your name (e.g. Alex)", text: $yourName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Who's it for? (e.g. Sam)", text: $theirName)
                        .textFieldStyle(.roundedBorder)

                    Picker("Occasion", selection: $occasion) {
                        ForEach(Self.occasions, id: \.id) { occ in
                            Text("\(occ.emoji) \(occ.label)").tag(occ.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.coral)

                    Toggle("Add the event date", isOn: $includeDate)
                        .font(.bodyMedium)
                    if includeDate {
                        DatePicker("Event date", selection: $date, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .font(.bodyMedium)
                    }
                }
                .padding(16)
                .background(Color.cream)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Share — two-step: build the deck server-side (POST
                // /challenges → challengeId in the link), then hand off to the
                // share sheet. Server unreachable → legacy local-deck link so
                // sharing never blocks.
                if challengeId == nil && !serverUnavailable {
                    Button {
                        Task { await createServerChallenge() }
                    } label: {
                        HStack {
                            Spacer()
                            if isCreating {
                                ProgressView().tint(.white)
                                Text("Building their deck…").font(.labelBold)
                            } else {
                                Image(systemName: "wand.and.stars")
                                Text("Create the challenge").font(.labelBold)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 15)
                        .background(Color.coral)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    .disabled(isCreating)
                } else if let url = inviteURL {
                    ShareLink(
                        item: url,
                        subject: Text("Giftmaxxing challenge"),
                        message: Text(InviteLink.shareText)
                    ) {
                        HStack {
                            Spacer()
                            Image(systemName: "paperplane.fill")
                            Text("Share the challenge")
                                .font(.labelBold)
                            Spacer()
                        }
                        .padding(.vertical, 15)
                        .background(Color.coral)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                }

                if challengeId != nil {
                    Label(
                        "Deck ready — built around \(seedPostId != nil ? "your picked gift and lookalikes" : seedImage != nil ? "your photo" : "your taste") from the live catalog. Their verdict lands in Responses.",
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.coral)
                } else if serverUnavailable {
                    Label(
                        "Deck builder unreachable — sharing the classic challenge instead. It still collects their taste.",
                        systemImage: "wifi.slash"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                } else {
                    Text("The link opens in their browser — they swipe as a guest, and their gift taste shows up in your responses below.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Responses — the hard auth boundary.
                ChallengeResponsesSection()
            }
            .padding(16)
        }
        .background(Color.surface)
        .navigationTitle("Gift Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        // Personalization is baked into the server deck's META — editing any
        // field invalidates the created challenge so the next share rebuilds.
        .onChange(of: yourName) { _, _ in challengeId = nil; postedChallengeIdToDm = nil }
        .onChange(of: theirName) { _, _ in challengeId = nil; postedChallengeIdToDm = nil }
        .onChange(of: occasion) { _, _ in challengeId = nil; postedChallengeIdToDm = nil }
        .onChange(of: includeDate) { _, _ in challengeId = nil; postedChallengeIdToDm = nil }
        .onChange(of: date) { _, _ in challengeId = nil; postedChallengeIdToDm = nil }
        .onAppear {
            if theirName.isEmpty, !prefillTheirName.isEmpty {
                theirName = prefillTheirName
            }
            if yourName.isEmpty {
                yourName = authManager.displayName ?? ""
            }
            appState.suppressMaxiFAB()
        }
        .onChange(of: authManager.displayName) { _, name in
            if yourName.isEmpty { yourName = name ?? "" }
        }
        .onDisappear { appState.unsuppressMaxiFAB() }
    }
}

// ── Responses (auth-gated, mirrors web "Seeing results needs auth") ──────────
struct ChallengeResponsesSection: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var connections: [SoftConnectionItem] = []
    @State private var isLoading = false
    @State private var loadFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Responses")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)

            if !authManager.isAuthenticated {
                SignInWall()
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else if loadFailed {
                Text("Couldn't load responses. Pull to refresh or try again later.")
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)
            } else if connections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No responses yet — share your challenge!")
                        .font(.bodyMedium)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            } else {
                ForEach(connections) { conn in
                    ResponseRow(connection: conn)
                }
            }
        }
        .task { await load() }
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated { Task { await load() } }
        }
    }

    private func load() async {
        guard authManager.isAuthenticated, let userId = authManager.userId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            connections = try await APIClient.shared.fetchConnections(userId: userId)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}

// The conversion wall: creating/sharing stayed open, results require identity.
struct SignInWall: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.coral)
            Text("Sign in to see responses")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.ink)
            Text("Anyone can share a challenge, but responses are private to your account. Everything collected so far is saved and appears the moment you sign in.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ResponseRow: View {
    let connection: SoftConnectionItem

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: connection.guestName, grad: .lilac, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(connection.guestName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)
                if let vibes = connection.vibes, !vibes.isEmpty {
                    Text(vibes.prefix(4).joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let yes = connection.yesCount, let total = connection.totalSwipes, total > 0 {
                    Text("\(yes) of \(total) swipes were a yes")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.coral)
                }
            }

            Spacer()

            if connection.seen != true {
                Circle()
                    .fill(Color.coral)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(12)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// Compact thumbnail card for picking the deck's seed gift.
private struct SeedPickCard: View {
    let post: Post
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    if post.product.image != nil {
                        CachedAsyncImage(url: post.product.image, width: 200)
                            .frame(width: 100, height: 100)
                            .clipped()
                    } else {
                        ZStack {
                            Color.gradient(for: post.product.grad)
                            Text(post.product.emoji).font(.system(size: 30))
                        }
                        .frame(width: 100, height: 100)
                    }
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.coral)
                            .background(Circle().fill(.white))
                            .padding(5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.coral : Color.clear, lineWidth: 2.5)
                )

                Text(post.product.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: 100, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}
