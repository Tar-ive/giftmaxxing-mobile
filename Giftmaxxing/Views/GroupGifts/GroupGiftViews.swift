import SwiftUI

// ── Group gifts — the "swipe together" context ───────────────────────────────
// One friend starts it, everyone swipes the same server-built deck, the tally
// converges on the gift, then the pledge round splits the cost. The recipient
// never sees the link.

// Embedded in SwipeView's "Group gift" context.
struct GroupGiftSection: View {
    @ObservedObject private var store = GroupGiftStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pick the gift together")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.ink)
                    Text("Start a deck for someone, invite the friend group to swipe, and watch the favorite emerge. Then everyone pledges their share.")
                        .font(.bodyMedium)
                        .foregroundStyle(.secondary)
                }

                NavigationLink(destination: GroupGiftCreateView()) {
                    HStack {
                        Spacer()
                        Image(systemName: "person.3.fill")
                        Text("Start a group gift").font(.labelBold)
                        Spacer()
                    }
                    .padding(.vertical, 15)
                    .background(Color.coral)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }

                if !store.gifts.isEmpty {
                    Text("YOUR GROUP GIFTS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    ForEach(store.gifts) { gift in
                        NavigationLink(destination: GroupGiftDetailView(giftId: gift.id)) {
                            GroupGiftRow(gift: gift)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.surface)
    }
}

private struct GroupGiftRow: View {
    let gift: GroupGift

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: gift.recipient, grad: .lilac, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("For \(gift.recipient)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text(gift.poolId != nil
                     ? "Pledge round underway"
                     : (gift.youSwiped ? "Waiting on the group…" : "Your swipe is missing!"))
                    .font(.system(size: 12))
                    .foregroundStyle(gift.youSwiped || gift.poolId != nil ? .secondary : Color.coral)
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
}

// ── Create ────────────────────────────────────────────────────────────────────
struct GroupGiftCreateView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // Optional capture seed (visual search / share extension): the deck is
    // built around this image — "we all saw this post, gift them THIS vibe."
    var seedImage: UIImage? = nil

    @State private var recipient = ""
    @State private var yourName = ""
    @State private var occasion = "birthday"
    @State private var isCreating = false
    @State private var createdGift: GroupGift?
    @State private var errorMessage: String?
    @State private var showSwipeSheet = false

    private static let occasions: [(id: String, label: String)] = [
        ("birthday", "🎂 Birthday"), ("anniversary", "💝 Anniversary"),
        ("wedding", "💒 Wedding"), ("graduation", "🎓 Graduation"),
        ("holiday", "🎄 Holiday"), ("farewell", "👋 Farewell"),
        ("baby-shower", "🍼 Baby shower"), ("other", "✨ Just because"),
    ]

    private var senderId: String {
        appState.currentUser?.id ?? InteractionQueue.anonymousUserId
    }

    private var inviterName: String {
        yourName.isEmpty ? (appState.currentUser?.name ?? "A friend") : yourName
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let gift = createdGift {
                    successSection(gift)
                } else {
                    formSection
                }
            }
            .padding(16)
        }
        .background(Color.surface)
        .navigationTitle("Group gift")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSwipeSheet) {
            if let gift = createdGift {
                GroupSwipeSheet(gift: gift)
            }
        }
    }

    @ViewBuilder
    private var formSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Who's the lucky one?")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.ink)
            Text("We'll build a swipe deck around their vibe. Your friends swipe in their browser — no app, no sign-up — and the group favorite wins.")
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
        }

        if let seedImage {
            HStack(spacing: 12) {
                Image(uiImage: seedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text("Deck seeded with this capture — everyone swipes gifts around it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.coralSoft.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }

        VStack(alignment: .leading, spacing: 14) {
            TextField("Who's it for? (e.g. Sarah)", text: $recipient)
                .textFieldStyle(.roundedBorder)
            TextField("Your name (e.g. Alex)", text: $yourName)
                .textFieldStyle(.roundedBorder)
            Picker("Occasion", selection: $occasion) {
                ForEach(Self.occasions, id: \.id) { occ in
                    Text(occ.label).tag(occ.id)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.coral)
        }
        .padding(16)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))

        Button {
            Task { await create() }
        } label: {
            HStack {
                Spacer()
                if isCreating {
                    ProgressView().tint(.white)
                    Text("Building the deck…").font(.labelBold)
                } else {
                    Image(systemName: "wand.and.stars")
                    Text("Build the group deck").font(.labelBold)
                }
                Spacer()
            }
            .padding(.vertical, 15)
            .background(recipient.trimmingCharacters(in: .whitespaces).isEmpty ? Color.coral.opacity(0.4) : Color.coral)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .disabled(isCreating || recipient.trimmingCharacters(in: .whitespaces).isEmpty)

        if let errorMessage {
            Label(errorMessage, systemImage: "wifi.slash")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func successSection(_ gift: GroupGift) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Deck ready for \(gift.recipient)", systemImage: "checkmark.seal.fill")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.coral)
            Text("Now rally the group — everyone who swipes shows up on the tally. You should swipe too!")
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
        }

        if let url = URL(string: gift.inviteURL) {
            ShareLink(
                item: url,
                subject: Text("Help pick a gift for \(gift.recipient)"),
                message: Text("Help me pick a gift for \(gift.recipient) — swipe what you think they'd love 🎁")
            ) {
                HStack {
                    Spacer()
                    Image(systemName: "paperplane.fill")
                    Text("Invite friends to swipe").font(.labelBold)
                    Spacer()
                }
                .padding(.vertical, 15)
                .background(Color.coral)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
        }

        Button {
            showSwipeSheet = true
        } label: {
            HStack {
                Spacer()
                Image(systemName: "hand.draw.fill")
                Text("Swipe the deck yourself").font(.labelBold)
                Spacer()
            }
            .padding(.vertical, 14)
            .background(Color.coral.opacity(0.12))
            .foregroundStyle(Color.coral)
            .clipShape(Capsule())
        }

        NavigationLink(destination: GroupGiftDetailView(giftId: gift.id)) {
            HStack {
                Spacer()
                Text("See the tally").font(.labelBold)
                Spacer()
            }
            .padding(.vertical, 14)
            .foregroundStyle(.secondary)
        }
    }

    private func create() async {
        guard !isCreating else { return }
        isCreating = true
        defer { isCreating = false }

        var imageBase64: String?
        if let seedImage {
            imageBase64 = seedImage.resized(maxDimension: 512)
                .jpegData(compressionQuality: 0.8)?
                .base64EncodedString()
        }
        var seedKeys: [String] = []
        if imageBase64 == nil {
            seedKeys = await TasteProfileStore.shared.snapshot().seedKeys
        }
        guard imageBase64 != nil || !seedKeys.isEmpty else {
            errorMessage = "Swipe a few gifts first (or seed with a photo) so we know the group's starting vibe."
            return
        }

        do {
            let trimmedRecipient = recipient.trimmingCharacters(in: .whitespaces)
            let response = try await APIClient.shared.createChallenge(
                senderId: senderId,
                mode: "group",
                seedImageBase64: imageBase64,
                seedKeys: seedKeys.isEmpty ? nil : seedKeys,
                inviterName: inviterName,
                to: trimmedRecipient,
                occasion: occasion == "other" ? nil : occasion
            )
            guard let url = InviteLink.buildURL(
                inviterName: inviterName,
                senderId: senderId,
                to: trimmedRecipient,
                occasion: occasion == "other" ? nil : occasion,
                date: nil,
                challengeId: response.challengeId
            ) else {
                errorMessage = "Couldn't build the invite link."
                return
            }
            createdGift = GroupGiftStore.shared.add(
                challengeId: response.challengeId,
                recipient: trimmedRecipient,
                occasion: occasion == "other" ? nil : occasion,
                inviterName: inviterName,
                inviteURL: url.absoluteString
            )
            errorMessage = nil
        } catch {
            errorMessage = "Deck builder unreachable — try again in a moment."
        }
    }
}

// ── Detail: tally + pledge round ─────────────────────────────────────────────
struct GroupGiftDetailView: View {
    let giftId: String

    @ObservedObject private var store = GroupGiftStore.shared
    @ObservedObject private var pools = PoolsStore.shared
    @State private var status: ChallengeStatusResponse?
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var showSwipeSheet = false
    @State private var showPledgeSheet = false

    private var gift: GroupGift? {
        store.gifts.first { $0.id == giftId }
    }

    private var pool: Pool? {
        guard let poolId = gift?.poolId else { return nil }
        return pools.pools.first { $0.id == poolId }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let gift {
                    header(gift)

                    if let pool {
                        PledgeLeaderboard(pool: pool, onPledge: { showPledgeSheet = true })
                    }

                    tallySection(gift)
                }
            }
            .padding(16)
        }
        .background(Color.surface)
        .navigationTitle(gift.map { "For \($0.recipient)" } ?? "Group gift")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
        .sheet(isPresented: $showSwipeSheet, onDismiss: { Task { await refresh() } }) {
            if let gift {
                GroupSwipeSheet(gift: gift)
            }
        }
        .sheet(isPresented: $showPledgeSheet) {
            if let gift, let pool {
                RecordPledgeSheet(pool: pool, recipient: gift.recipient)
                    .presentationDetents([.height(320)])
            }
        }
    }

    @ViewBuilder
    private func header(_ gift: GroupGift) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let count = status?.responders?.count ?? status?.responseCount ?? 0
            Text(count == 0
                 ? "No swipes yet — get the group going"
                 : "\(count) swiped so far")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.ink)

            if let responders = status?.responders, !responders.isEmpty {
                Text(responders.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if let url = URL(string: gift.inviteURL) {
                    ShareLink(
                        item: url,
                        message: Text("Help me pick a gift for \(gift.recipient) — swipe what you think they'd love 🎁")
                    ) {
                        Label("Invite", systemImage: "paperplane.fill")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.coral)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                Button {
                    showSwipeSheet = true
                } label: {
                    Label(gift.youSwiped ? "Swipe again" : "Swipe the deck", systemImage: "hand.draw.fill")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.coral.opacity(0.12))
                        .foregroundStyle(Color.coral)
                        .clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func tallySection(_ gift: GroupGift) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("THE GROUP'S FAVORITES")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            if isLoading && status == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else if loadFailed && status == nil {
                Text("Couldn't reach the tally — pull to refresh.")
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)
            } else if let picks = status?.groupPicks, !picks.isEmpty {
                ForEach(Array(picks.prefix(8).enumerated()), id: \.element.id) { index, pick in
                    GroupPickRow(rank: index + 1, pick: pick)
                }

                if gift.poolId == nil, let top = status?.groupPicks?.first {
                    Button {
                        startPledgeRound(gift: gift, winner: top)
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "dollarsign.circle.fill")
                            Text("Start the pledge round").font(.labelBold)
                            Spacer()
                        }
                        .padding(.vertical, 15)
                        .background(Color.coral)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                    Text("Locks in the group's current favorite — everyone chips in their share.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.person.crop")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("The tally appears as friends swipe.")
                        .font(.bodyMedium)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }
        }
    }

    private func startPledgeRound(gift: GroupGift, winner: ChallengeStatusResponse.GroupPickItem) {
        let price = winner.price ?? 50
        let product = Product(
            id: winner.postId,
            name: winner.name ?? "The group's pick",
            brand: "Group favorite",
            price: price,
            was: nil,
            grad: .coral,
            emoji: "🎁",
            image: winner.image
        )
        let pool = PoolsStore.shared.create(
            title: winner.name ?? "Gift for \(gift.recipient)",
            forUser: gift.recipient,
            occasion: gift.occasion ?? "",
            targetAmount: price,
            product: product
        )
        store.attachPool(pool.id, to: gift.id)
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            status = try await APIClient.shared.fetchChallengeStatus(challengeId: giftId)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}

private struct GroupPickRow: View {
    let rank: Int
    let pick: ChallengeStatusResponse.GroupPickItem

    private var medal: String? {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(medal ?? "#\(rank)")
                .font(.system(size: medal != nil ? 22 : 14, weight: .bold))
                .frame(width: 32)

            if let image = pick.image {
                CachedAsyncImage(url: image, width: 120)
                    .frame(width: 52, height: 52)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.coralSoft)
                    .frame(width: 52, height: 52)
                    .overlay(Text("🎁"))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(pick.name ?? "Gift idea")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                if let guests = pick.guests, !guests.isEmpty {
                    Text(guests.prefix(4).joined(separator: ", "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Label("\(pick.yes)", systemImage: "heart.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.coral)
                if let price = pick.price, price > 0 {
                    Text("$\(Int(price))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// ── Pledge leaderboard ───────────────────────────────────────────────────────
struct PledgeLeaderboard: View {
    let pool: Pool
    var onPledge: () -> Void

    private var ranked: [PoolContributor] {
        pool.contributors.sorted { $0.amount > $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PLEDGES")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("$\(Int(pool.currentAmount)) of $\(Int(pool.targetAmount))")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.coral)
            }

            ProgressView(value: pool.progressPercent)
                .tint(Color.coral)

            if ranked.isEmpty {
                Text("No pledges yet — kick it off below.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, contributor in
                    HStack(spacing: 10) {
                        Text(index == 0 ? "🥇" : index == 1 ? "🥈" : index == 2 ? "🥉" : "#\(index + 1)")
                            .font(.system(size: index < 3 ? 18 : 13, weight: .bold))
                            .frame(width: 28)
                        AvatarView(name: contributor.name, grad: contributor.avatarGrad, size: 32)
                        Text(contributor.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.ink)
                        Spacer()
                        Text("$\(Int(contributor.amount))")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.coral)
                    }
                }
            }

            Button {
                onPledge()
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                    Text("Add a pledge").font(.labelBold)
                    Spacer()
                }
                .padding(.vertical, 13)
                .background(Color.coral.opacity(0.12))
                .foregroundStyle(Color.coral)
                .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// Record a pledge — yours or a friend's ("Sarah Venmo'd $25"). Payments and
// delivery are deliberately out of scope for now; the leaderboard is the
// coordination layer.
struct RecordPledgeSheet: View {
    let pool: Pool
    let recipient: String

    @Environment(\.dismiss) private var dismiss
    @State private var name = "You"
    @State private var amount: Double = 25

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            Text("Pledge toward \(recipient)'s gift")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.ink)

            TextField("Who's pledging?", text: $name)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)

            HStack(spacing: 10) {
                ForEach([10, 25, 50], id: \.self) { preset in
                    Button {
                        amount = Double(preset)
                    } label: {
                        Text("$\(preset)")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(amount == Double(preset) ? Color.coral : Color.cream)
                            .foregroundStyle(amount == Double(preset) ? .white : Color.ink)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)

            Stepper("$\(Int(amount))", value: $amount, in: 1...500, step: 5)
                .font(.system(size: 16, weight: .bold))
                .padding(.horizontal, 20)

            Button {
                PoolsStore.shared.pledge(
                    name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "You" : name,
                    amount: amount,
                    to: pool.id
                )
                dismiss()
            } label: {
                HStack {
                    Spacer()
                    Text("Pledge $\(Int(amount))").font(.labelBold)
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(Color.coral)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color.surface)
    }
}

// ── In-app deck swiper (the creator swipes the same deck friends get) ────────
struct GroupSwipeSheet: View {
    let gift: GroupGift

    @Environment(\.dismiss) private var dismiss
    @State private var deck: [ChallengeCreateResponse.ChallengeDeckItem] = []
    @State private var index = 0
    @State private var swipes: [(id: String, dir: String)] = []
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            Text("Would \(gift.recipient) love it?")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.ink)

            if isLoading {
                Spacer()
                ProgressView("Loading the deck…")
                Spacer()
            } else if failed {
                Spacer()
                Text("Couldn't load the deck — try again later.")
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)
                Spacer()
            } else if submitted {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.coral)
                    Text("Your picks are on the tally!")
                        .font(.system(size: 17, weight: .bold))
                    Text("You said yes to \(swipes.filter { $0.dir == "yes" }.count) of \(swipes.count).")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Button("Done") { dismiss() }
                    .font(.labelBold)
                    .foregroundStyle(Color.coral)
                    .padding(.top, 8)
                Spacer()
            } else if index < deck.count {
                let item = deck[index]

                Text("\(index + 1)/\(deck.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    ZStack {
                        Color.coralSoft
                        if let image = item.image {
                            CachedAsyncImage(url: image, width: 600)
                                .frame(height: 300)
                                .clipped()
                        } else {
                            Text("🎁").font(.system(size: 64))
                        }
                    }
                    .frame(height: 300)
                    .clipped()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.name ?? "Gift idea")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.ink)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            if let price = item.price, price > 0 {
                                Text("$\(Int(price))")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Color.coral)
                                    .fixedSize()
                            }
                        }
                        if let category = item.category {
                            Text(category)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cream)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
                .padding(.horizontal, 20)

                HStack(spacing: 40) {
                    Button {
                        record("no")
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: 58, height: 58)
                            .background(Color.cream)
                            .clipShape(Circle())
                    }
                    Button {
                        record("yes")
                    } label: {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.coral)
                            .frame(width: 58, height: 58)
                            .background(Color.cream)
                            .clipShape(Circle())
                    }
                }
                .padding(.bottom, 12)
            } else if isSubmitting {
                Spacer()
                ProgressView("Sending your picks…")
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surface)
        .task { await loadDeck() }
    }

    private func record(_ dir: String) {
        guard index < deck.count else { return }
        swipes.append((id: deck[index].postId, dir: dir))
        index += 1
        if index >= deck.count {
            Task { await submit() }
        }
    }

    private func loadDeck() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let status = try await APIClient.shared.fetchChallengeStatus(challengeId: gift.id)
            deck = status.deck ?? []
            failed = deck.isEmpty
        } catch {
            failed = true
        }
    }

    private func submit() async {
        guard !isSubmitting, !swipes.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await APIClient.shared.submitChallengeResponse(
                challengeId: gift.id,
                guestName: gift.inviterName,
                swipes: swipes
            )
            GroupGiftStore.shared.markSwiped(gift.id)
            submitted = true
        } catch {
            failed = true
        }
    }
}
