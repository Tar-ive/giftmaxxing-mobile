import SwiftUI

// The Gift Concierge consult (mirrors web/components/app/gift-consult.tsx).
//
// One component, two homes:
//   • the Concierge TAB — talk to Maxi any time you owe someone a gift;
//   • ONBOARDING (isOnboarding: true) — new users meet Maxi by running their
//     first real consult; the answers double as their taste profile
//     (genderPref + world vibes → PersonalizationStore + PUT /me).
//
// Who are we gifting, what's their world, budget OPTIONAL ("just find the
// gift" is a first-class answer). The consult ends in a real pick from the
// catalog with two doors:
//   1. Get it — outbound retailer link, done.
//   2. Double-check — POST /challenges mode="verify" hides the pick in a
//      ~14-card swipe deck; if the recipient right-swipes it without knowing
//      it was the ask, GET /challenges/{id}.verify reports a confirmed match.
//
// Ranking is the same move-test heuristic the web consult uses (lib/consult.ts
// ported 1:1): category durability + keep/clutter text signals + interest and
// budget fit. Deterministic — no LLM behind the conversation.

// MARK: - Consult metadata (ported from web/lib/consult.ts)

private struct ConsultChip: Identifiable {
    let key: String
    let label: String
    let emoji: String
    var id: String { key }
}

private enum ConsultMeta {
    static let relations: [ConsultChip] = [
        .init(key: "partner", label: "My partner", emoji: "💞"),
        .init(key: "mom", label: "My mom", emoji: "🌷"),
        .init(key: "dad", label: "My dad", emoji: "🧢"),
        .init(key: "sibling", label: "My sibling", emoji: "🧑‍🤝‍🧑"),
        .init(key: "friend", label: "A friend", emoji: "🫂"),
        .init(key: "coworker", label: "A coworker", emoji: "💼"),
        .init(key: "kid", label: "A kid", emoji: "🧒"),
        .init(key: "other", label: "Someone else", emoji: "🎁"),
    ]

    static let recipientKey: [String: String] = [
        "partner": "partner", "mom": "mom", "dad": "dad", "friend": "friend",
        "coworker": "coworker", "kid": "kids",
    ]

    static let occasions: [ConsultChip] = [
        .init(key: "birthday", label: "Birthday", emoji: "🎂"),
        .init(key: "anniversary", label: "Anniversary", emoji: "💝"),
        .init(key: "housewarming", label: "Housewarming", emoji: "🏡"),
        .init(key: "wedding", label: "Wedding", emoji: "💒"),
        .init(key: "graduation", label: "Graduation", emoji: "🎓"),
        .init(key: "holiday", label: "Holidays", emoji: "🎄"),
        .init(key: "any", label: "Just because", emoji: "✨"),
    ]

    static let worlds: [ConsultChip] = [
        .init(key: "kitchen", label: "Cooks & hosts", emoji: "🍳"),
        .init(key: "home", label: "Homebody", emoji: "🛋️"),
        .init(key: "style", label: "Fashion & style", emoji: "🧥"),
        .init(key: "jewelry", label: "Jewelry & keepsakes", emoji: "💍"),
        .init(key: "making", label: "Art & making things", emoji: "🎨"),
        .init(key: "tech", label: "Tech & gadgets", emoji: "🔌"),
        .init(key: "outdoors", label: "Outdoorsy", emoji: "🏕️"),
        .init(key: "wellness", label: "Wellness & self-care", emoji: "🧘"),
        .init(key: "books", label: "Books & words", emoji: "📚"),
        .init(key: "music", label: "Music", emoji: "🎶"),
        .init(key: "pets", label: "Pet person", emoji: "🐾"),
        .init(key: "games", label: "Games & play", emoji: "🎲"),
    ]

    static let worldCategories: [String: [String]] = [
        "kitchen": ["kitchen", "drinkware", "food"],
        "home": ["home", "garden"],
        "style": ["fashion", "accessories"],
        "jewelry": ["jewelry"],
        "making": ["art", "art_handmade", "stationery"],
        "tech": ["tech", "photography"],
        "outdoors": ["outdoors", "fitness", "garden"],
        "wellness": ["wellness", "beauty"],
        "books": ["books", "stationery"],
        "music": ["music"],
        "pets": ["pets"],
        "games": ["games", "kids"],
    ]

    static let keepers: [ConsultChip] = [
        .init(key: "kitchen", label: "Their kitchen gear", emoji: "🍳"),
        .init(key: "keepsakes", label: "Jewelry & keepsakes", emoji: "💍"),
        .init(key: "shelf", label: "Books & art", emoji: "🖼️"),
        .init(key: "setup", label: "Their tech setup", emoji: "🖥️"),
        .init(key: "comfort", label: "The comfort things", emoji: "🕯️"),
        .init(key: "light", label: "Honestly? They travel light", emoji: "🎒"),
    ]

    static let keeperBoost: [String: [String]] = [
        "kitchen": ["kitchen", "drinkware"],
        "keepsakes": ["jewelry", "art_handmade"],
        "shelf": ["books", "art", "music"],
        "setup": ["tech", "photography", "games"],
        "comfort": ["home", "wellness"],
        "light": [],
    ]

    // World → vibe facets (same vocabulary the server's scorePost boosts).
    static let worldVibes: [String: [String]] = [
        "kitchen": ["kitchen", "foodie"],
        "home": ["cozy", "home"],
        "style": ["minimal", "luxe"],
        "jewelry": ["luxe", "romantic"],
        "making": ["aesthetic", "diy"],
        "tech": ["tech"],
        "outdoors": ["outdoors"],
        "wellness": ["calm", "wellness"],
        "books": ["calm", "stationery"],
        "music": ["retro"],
        "pets": ["warm"],
        "games": ["retro"],
    ]

    // World → the web profile's interest tags (kept in sync with
    // web/lib/consult.ts WORLD_INTERESTS so both platforms write the same
    // profile shape to /me).
    static let worldInterests: [String: [String]] = [
        "kitchen": ["foodie", "coffee-tea"],
        "home": ["cozy", "plants", "candles"],
        "style": ["minimalist", "vintage"],
        "jewelry": ["luxury"],
        "making": ["diy", "stationery"],
        "tech": ["photography", "pop-culture"],
        "outdoors": ["outdoors", "sustainable"],
        "wellness": ["wellness"],
        "books": ["stationery", "cozy"],
        "music": ["vintage", "pop-culture"],
        "pets": ["pets"],
        "games": ["pop-culture"],
    ]

    static let genderOptions: [ConsultChip] = [
        .init(key: "him", label: "Gifts for him", emoji: "🤵"),
        .init(key: "her", label: "Gifts for her", emoji: "👩"),
        .init(key: "any", label: "Mix of everyone", emoji: "🎁"),
    ]

    static let budgets: [Double] = [25, 50, 100, 250]
}

// MARK: - Move test + ranking (port of lib/consult.ts)

private struct RankedGift: Identifiable {
    let post: Post
    let score: Double
    let packVerdict: String // "pack" | "probably"
    let reason: String
    var id: String { post.id }

    var verdictLabel: String { packVerdict == "pack" ? "📦 Would pack it" : "👍 Keeps it" }
}

private enum ConsultRanker {
    static let durability: [String: Double] = [
        "jewelry": 0.9, "kitchen": 0.8, "books": 0.8, "art": 0.75, "art_handmade": 0.8,
        "music": 0.75, "tech": 0.7, "photography": 0.7, "home": 0.68, "drinkware": 0.65,
        "garden": 0.6, "outdoors": 0.62, "games": 0.6, "pets": 0.55, "fashion": 0.55,
        "accessories": 0.55, "stationery": 0.5, "fitness": 0.55, "kids": 0.5,
        "wellness": 0.45, "food": 0.3, "beauty": 0.35,
    ]

    static let keepSignals: [(String, Double, String)] = [
        ("personali[sz]ed|custom|engraved|monogram|initial", 0.15, "made for them specifically"),
        ("handmade|hand.?crafted|artisan", 0.12, "handmade — has a story"),
        ("solid wood|walnut|oak|leather|ceramic|cast iron|stoneware|brass|copper|linen|marble|wool", 0.1, "real materials that age well"),
        ("heirloom|keepsake|forever|lifetime", 0.15, "built to be kept"),
        ("\\bset\\b|kit\\b", 0.04, "a complete set, not a spare part"),
        ("mug|knife|blanket|throw|lamp|vase|board|journal|tote|necklace|ring|bracelet|watch|frame|print|planter", 0.06, "something they'd actually use"),
    ]

    static let clutterSignals: [(String, Double, String)] = [
        ("novelty|gag|prank|funny mug|joke", 0.35, "novelty wears off"),
        ("figurine|trinket|knick.?knack|desk toy", 0.2, "shelf clutter risk"),
        ("plastic|disposable|single.?use", 0.15, "won't survive a move"),
        ("keychain|sticker|magnet", 0.15, "too small to register"),
    ]

    static func moveTest(name: String, category: String?, price: Double) -> (score: Double, verdict: String, reason: String) {
        var score = durability[category ?? "misc"] ?? 0.5
        var reason: String?
        for (pattern, boost, why) in keepSignals where matches(name, pattern) {
            score += boost
            if reason == nil { reason = why }
        }
        for (pattern, penalty, why) in clutterSignals where matches(name, pattern) {
            score -= penalty
            reason = why
        }
        if price > 0 && price < 12 { score -= 0.1 }
        score = max(0, min(1, score))
        let verdict = score >= 0.7 ? "pack" : score >= 0.5 ? "probably" : "clutter"
        let fallback = verdict == "pack"
            ? "the kind of thing that makes it into the box"
            : verdict == "probably" ? "useful enough to keep around" : "might not survive the move"
        return (score, verdict, reason ?? fallback)
    }

    static func rank(posts: [Post], worlds: Set<String>, keeper: String?, budget: Double?, audience: String? = nil, n: Int = 9) -> [RankedGift] {
        var categories: [String] = []
        var seenCat = Set<String>()
        for boost in ConsultMeta.keeperBoost[keeper ?? ""] ?? [] where !seenCat.contains(boost) {
            if worlds.contains(where: { (ConsultMeta.worldCategories[$0] ?? []).contains(boost) }) {
                seenCat.insert(boost)
                categories.append(boost)
            }
        }
        for w in worlds {
            for c in ConsultMeta.worldCategories[w] ?? [] where !seenCat.contains(c) {
                seenCat.insert(c)
                categories.append(c)
            }
        }
        if categories.isEmpty { categories = ConsultMeta.keeperBoost[keeper ?? ""] ?? [] }
        let catRank = Dictionary(uniqueKeysWithValues: categories.enumerated().map { ($1, $0) })
        let minimalist = keeper == "light"

        var seen = Set<String>()
        var out: [RankedGift] = []
        for post in posts {
            guard !seen.contains(post.id) else { continue }
            seen.insert(post.id)
            let price = post.product.price
            guard price > 0 else { continue }
            if let budget, price > budget * 1.15 { continue }

            // The consult KNOWS who the gift is for — never show a "for him"
            // asker something that reads unmistakably feminine (or vice versa).
            // Neutral items (books, mugs, decks) pass; only clear opposites drop.
            let inferredAudience = AudienceClassifier.infer(for: post)
            if let audience, let inferredAudience, inferredAudience != audience { continue }

            let move = moveTest(name: post.product.name, category: post.category, price: price)
            guard move.verdict != "clutter" else { continue }

            let rank = catRank[post.category ?? ""]
            let interest = rank == nil ? 0.25 : max(0.4, 1 - Double(rank!) * 0.15)
            let fit: Double
            if let budget {
                fit = price <= budget ? 0.7 + 0.3 * min(1, price / (budget * 0.45)) : 0.55
            } else {
                fit = 0.7
            }
            let wMove = minimalist ? 0.55 : 0.45
            var score = wMove * move.score + 0.35 * interest + (1 - wMove - 0.35) * fit
            // Items that explicitly read as the right audience edge ahead of
            // neutral ones ("men's leather journal" over "journal").
            if let audience, inferredAudience == audience { score += 0.08 }
            out.append(RankedGift(post: post, score: score, packVerdict: move.verdict, reason: move.reason))
        }
        out.sort { $0.score > $1.score }

        // Variety: max 3 per category.
        var byCat: [String: Int] = [:]
        var picked: [RankedGift] = []
        for g in out {
            let c = g.post.category ?? "misc"
            if byCat[c, default: 0] >= 3 { continue }
            byCat[c, default: 0] += 1
            picked.append(g)
            if picked.count >= n { break }
        }
        return picked
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

// MARK: - View model

@MainActor
private final class ConsultViewModel: ObservableObject {
    enum Phase: Int {
        case intro, gender, relation, name, occasion, budget, worlds, keeper, thinking, results
    }

    @Published var phase: Phase = .intro
    @Published var genderPref: String?
    @Published var relation: String?
    @Published var theirName = ""
    @Published var occasion: String?
    @Published var budget: Double?
    @Published var budgetText = ""
    @Published var worlds: Set<String> = []
    @Published var keeper: String?
    @Published var gifts: [RankedGift] = []

    // Verify flow
    @Published var verifyChallengeId: String?
    @Published var verifyURL: URL?
    @Published var verifyCreating = false
    @Published var verifyError = false
    @Published var verifySummary: ChallengeStatusResponse.VerifySummary?

    var who: String {
        let n = theirName.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "them" : n
    }

    private var senderId: String {
        AuthManager.shared.userId ?? InteractionQueue.anonymousUserId
    }

    func reset() {
        phase = .intro
        relation = nil
        theirName = ""
        occasion = nil
        budget = nil
        budgetText = ""
        worlds = []
        keeper = nil
        gifts = []
        verifyChallengeId = nil
        verifyURL = nil
        verifyCreating = false
        verifyError = false
        verifySummary = nil
    }

    // Onboarding: the consult answers ARE the user's taste profile.
    //  • locally → PersonalizationStore (cold-start feed facets, instant);
    //  • cloud   → PUT /me with the web-compatible profile shape, but ONLY
    //    when this account has no completed profile anywhere (PUT replaces).
    func persistOnboardingSignals() {
        if let genderPref { PersonalizationStore.genderPref = genderPref }
        var vibes: [String] = []
        for w in worlds {
            for v in ConsultMeta.worldVibes[w] ?? [] where !vibes.contains(v) { vibes.append(v) }
        }
        if !vibes.isEmpty { PersonalizationStore.consultVibes = vibes }

        var interests: [String] = []
        for w in worlds {
            for tag in ConsultMeta.worldInterests[w] ?? [] where !interests.contains(tag) {
                interests.append(tag)
            }
        }
        for tag in ["cozy", "foodie", "wellness"] where interests.count < 3 {
            if !interests.contains(tag) { interests.append(tag) }
        }
        let genderValue = genderPref
        let budgetValue = budget

        // Home listens for this and refetches with the new facets.
        NotificationCenter.default.post(name: .consultProfileUpdated, object: nil)

        Task {
            guard let uid = AuthManager.shared.userId else { return }
            do {
                let existing = try await APIClient.shared.fetchMe(userId: uid)
                guard existing?.completedAt == nil else { return }
                var profile: [String: Any] = [
                    "name": AuthManager.shared.displayName ?? existing?.name ?? "Gifter",
                    "role": "giver",
                    "difficulty": "moderate",
                    "style": "thoughtful",
                    "materialisticCategories": [String](),
                    "interests": interests,
                    "dealPreferences": [
                        "sensitivity": "value-conscious",
                        "budgetRange": budgetValue.map { $0 <= 40 ? "budget" : $0 <= 120 ? "mid" : "premium" } ?? "no-limit",
                        "dealTypes": ["price-drops"],
                        "priceAlerts": false,
                    ] as [String: Any],
                    "pinterestLinks": [String](),
                    "completedAt": Date().timeIntervalSince1970 * 1000,
                ]
                if let genderValue { profile["genderPref"] = genderValue }
                if let email = existing?.email ?? AuthManager.shared.email { profile["email"] = email }
                try await APIClient.shared.saveMeRaw(userId: uid, profile: profile)
            } catch {
                // Offline — local personalization still applies; the web/next
                // launch can complete the cloud write.
            }
        }
    }

    // The recipient's audience ("men"/"women") from the consult's own answers:
    // the explicit him/her question first, the relation (dad/mom) as fallback.
    // Drives both the catalog facet and the hard audience gate in the ranker.
    var recipientAudience: String? {
        switch genderPref {
        case "him": return "men"
        case "her": return "women"
        default: break
        }
        switch relation {
        case "dad": return "men"
        case "mom": return "women"
        default: return nil
        }
    }

    func runConsult() async {
        phase = .thinking
        // The catalog's recipient facet only knows men/women/anyone — relation
        // keys like "dad" match nothing, so prefer the derived audience.
        let recipient = recipientAudience ?? ConsultMeta.recipientKey[relation ?? ""]
        let occ = occasion == "any" ? nil : occasion
        let category = worlds.compactMap { ConsultMeta.worldCategories[$0]?.first }.first

        async let targeted = try? APIClient.shared.fetchFeed(
            limit: 50, recipient: recipient, occasion: occ, category: category, budget: budget
        )
        async let broad = try? APIClient.shared.fetchFeed(limit: 50, budget: budget)
        let posts = ((await targeted)?.posts ?? []) + ((await broad)?.posts ?? [])

        gifts = ConsultRanker.rank(posts: posts, worlds: worlds, keeper: keeper, budget: budget, audience: recipientAudience)
        try? await Task.sleep(nanoseconds: 1_200_000_000) // let the beat land
        phase = .results
    }

    func rebudget(_ newBudget: Double?) async {
        budget = newBudget
        await runConsult()
    }

    // The double-check: hide the pick in a verify deck, share the link.
    func createVerifyChallenge(top: RankedGift) async {
        guard !verifyCreating, verifyChallengeId == nil else { return }
        verifyCreating = true
        verifyError = false
        defer { verifyCreating = false }
        do {
            let res = try await APIClient.shared.createChallenge(
                senderId: senderId,
                mode: "verify",
                seedPostId: top.post.id,
                to: theirName.isEmpty ? nil : theirName,
                occasion: occasion == "any" ? nil : occasion
            )
            verifyChallengeId = res.challengeId
            verifyURL = InviteLink.buildURL(
                inviterName: "A friend",
                senderId: senderId,
                to: theirName.isEmpty ? nil : theirName,
                challengeId: res.challengeId
            )
        } catch {
            verifyError = true
        }
    }

    func pollVerify() async {
        guard let id = verifyChallengeId else { return }
        if let status = try? await APIClient.shared.fetchChallengeStatus(challengeId: id) {
            verifySummary = status.verify
        }
    }
}

// MARK: - The view

struct ConsultView: View {
    // Onboarding mode: gender question first, profile persisted on finish,
    // "Skip for now" escape hatch. Tab mode: an always-available concierge.
    var isOnboarding = false
    var skipIntro = false
    var prefillRecipientName: String? = nil
    var onDone: (() -> Void)? = nil

    @StateObject private var vm = ConsultViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header

            switch vm.phase {
            case .intro:
                if skipIntro {
                    // The glassmorphism intro in OnboardingView replaces this;
                    // jump straight to the first question.
                    Color.clear.onAppear {
                        vm.phase = isOnboarding ? .gender : .relation
                    }
                } else {
                    IntroStep(isOnboarding: isOnboarding) {
                        vm.phase = isOnboarding ? .gender : .relation
                    }
                }
            case .thinking: ThinkingStep(vm: vm)
            case .results: ResultsStep(
                vm: vm,
                finishLabel: isOnboarding ? "Start exploring the app →" : "↺ Start another consult",
                finish: isOnboarding ? complete : { vm.reset() }
            )
            default: questionSteps
            }
        }
        .background(Color.onboardingWash.ignoresSafeArea())
        .interactiveDismissDisabled(isOnboarding && vm.phase != .results)
        .onAppear {
            guard let name = prefillRecipientName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, vm.theirName.isEmpty else { return }
            vm.relation = "friend"
            vm.theirName = name
            vm.phase = .occasion
        }

    }

    private func complete() {
        if isOnboarding { vm.persistOnboardingSignals() }
        onDone?()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("🎁").font(.system(size: 26))
            VStack(alignment: .leading, spacing: 1) {
                Text("Maxi").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Color.ink)
                Text("your gift concierge").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if isOnboarding, vm.phase != .results {
                Button("Skip for now") { complete() }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            } else if !isOnboarding, vm.phase != .intro {
                Button {
                    vm.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var questionSteps: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch vm.phase {
                case .gender:
                    QuestionTitle(
                        "Whose gifts should your feed lean toward?",
                        subtitle: "This one's about YOU — it shapes your Home feed. Consults work for anyone either way."
                    )
                    ChipGrid(chips: ConsultMeta.genderOptions, selected: vm.genderPref.map { [$0] } ?? []) { key in
                        vm.genderPref = key
                        vm.phase = .relation
                    }
                case .relation:
                    QuestionTitle("First — who are we gifting?")
                    ChipGrid(chips: ConsultMeta.relations, selected: vm.relation.map { [$0] } ?? []) { key in
                        vm.relation = key
                        vm.phase = .name
                    }
                case .name:
                    QuestionTitle("What do you call them?", subtitle: "First name is plenty.")
                    NameInput(vm: vm)
                case .occasion:
                    QuestionTitle("Got it. What's the occasion?")
                    ChipGrid(chips: ConsultMeta.occasions, selected: vm.occasion.map { [$0] } ?? []) { key in
                        vm.occasion = key
                        vm.phase = .budget
                    }
                case .budget:
                    QuestionTitle("What's the budget?", subtitle: "No number in mind? Skip it — I'll judge on the gift, not the price.")
                    BudgetInput(vm: vm)
                case .worlds:
                    QuestionTitle("What is \(vm.who) actually into?", subtitle: "Pick everything that's true — the overlap is where good gifts hide.")
                    ChipGrid(chips: ConsultMeta.worlds, selected: Array(vm.worlds), multi: true) { key in
                        if vm.worlds.contains(key) { vm.worlds.remove(key) } else { vm.worlds.insert(key) }
                    }
                    if !vm.worlds.isEmpty {
                        PrimaryButton("That's them →") { vm.phase = .keeper }
                    }
                case .keeper:
                    QuestionTitle("Last one, my favorite:", subtitle: "Think of the last time \(vm.who) moved. What came with them — no question, first box packed?")
                    ChipGrid(chips: ConsultMeta.keepers, selected: vm.keeper.map { [$0] } ?? []) { key in
                        vm.keeper = key
                        Task { await vm.runConsult() }
                    }
                default:
                    EmptyView()
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Steps

private struct IntroStep: View {
    var isOnboarding = false
    let start: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("🎁").font(.system(size: 72))
            VStack(spacing: 10) {
                Text("Hey — I'm Maxi.\nI find gifts people actually keep.")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                // The move test stays internal (it drives the ranking) — the
                // intro just says what Maxi does, not the theory behind it.
                Text(isOnboarding
                    ? "This is the whole app — tell me about a person, I find the gift. Let's run your first consult now."
                    : "Owe someone a gift? Tell me about them — a few sharp questions, then real picks from the live catalog.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            PrimaryButton("Find someone a gift →") { start() }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
    }
}

private struct ThinkingStep: View {
    @ObservedObject var vm: ConsultViewModel

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("🎁").font(.system(size: 56))
            Text("Okay — \(vm.who), \(vm.budget.map { "$\(Int($0)) to spend" } ?? "budget open").")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Pulling real options from the live catalog…")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            ProgressView().padding(.top, 8)
            Spacer()
        }
    }
}

private struct ResultsStep: View {
    @ObservedObject var vm: ConsultViewModel
    var finishLabel = "Start exploring the app →"
    let finish: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Text("📦").font(.system(size: 22))
                    Text("**The move test:** everything below is something \(vm.who) would pack, not purge, when they next move.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.7)))

                if let top = vm.gifts.first {
                    TopPickCard(gift: top)
                    VerifyPanel(vm: vm, top: top)
                } else {
                    Text("My catalog came up short for this one — explore the feed and I'll keep learning their taste.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                }

                if vm.gifts.count > 1 {
                    Text("ALSO STRONG")
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(1.5)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                        ForEach(vm.gifts.dropFirst()) { gift in
                            SmallGiftCard(gift: gift)
                        }
                    }
                }

                PrimaryButton(finishLabel) { finish() }
                    .padding(.top, 8)
            }
            .padding(20)
        }
    }
}

// MARK: - Result cards

private struct TopPickCard: View {
    let gift: RankedGift

    private var buyURL: URL? {
        URL(string: gift.post.productUrl ?? gift.post.url ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                GiftImage(urlString: gift.post.product.image, emoji: gift.post.product.emoji, grad: gift.post.product.grad, height: 220)
                Text("⭐ The pick")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.ink.opacity(0.85)))
                    .padding(10)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(gift.post.product.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                    Spacer()
                    Text("$\(Int(gift.post.product.price))")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.ink)
                }
                Text(gift.reason)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(gift.verdictLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color(hex: "#D1E7D4")))
                        .foregroundStyle(Color.ink)
                    Spacer()
                    if let buyURL {
                        Link(destination: buyURL) {
                            Label("Get it", systemImage: "gift.fill")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(Capsule().fill(Color(hex: "#FB6F52")))
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(RoundedRectangle(cornerRadius: 24).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.black.opacity(0.06)))
    }
}

private struct SmallGiftCard: View {
    let gift: RankedGift

    var body: some View {
        Link(destination: URL(string: gift.post.productUrl ?? gift.post.url ?? "") ?? URL(string: InviteLink.siteURL)!) {
            VStack(alignment: .leading, spacing: 0) {
                GiftImage(urlString: gift.post.product.image, emoji: gift.post.product.emoji, grad: gift.post.product.grad, height: 130)
                VStack(alignment: .leading, spacing: 4) {
                    Text(gift.post.product.name)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("$\(Int(gift.post.product.price))")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.ink)
                }
                .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06)))
        }
    }
}

private struct GiftImage: View {
    let urlString: String?
    let emoji: String
    let grad: GradientStyle
    let height: CGFloat

    var body: some View {
        ZStack {
            Color.gradient(for: grad)
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Text(emoji).font(.system(size: 40))
                }
            } else {
                Text(emoji).font(.system(size: 40))
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

// MARK: - The verify panel (double-check by swipe game)

private struct VerifyPanel: View {
    @ObservedObject var vm: ConsultViewModel
    let top: RankedGift

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if vm.verifyChallengeId == nil {
                Text("Not 100% sure? Ask \(vm.who) — sneakily.")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink)
                Text("I'll hide this pick in a deck of 14 cards. \(vm.who.capitalized) just swipes what they like — they'll never know which card was the ask. A right-swipe on your pick = confirmed match.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Button {
                    Task { await vm.createVerifyChallenge(top: top) }
                } label: {
                    Label(vm.verifyCreating ? "Building the deck…" : "Double-check with a swipe game",
                          systemImage: "rectangle.stack.badge.person.crop")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(Color.ink))
                }
                .disabled(vm.verifyCreating)
                if vm.verifyError {
                    Text("Couldn't build the deck — try again in a minute.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "#FB6F52"))
                }
            } else {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Swipe game is live 🎳")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.ink)
                        Text("Send it to \(vm.who). Your pick is hidden among 14 cards.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let url = vm.verifyURL {
                        ShareLink(item: url, message: Text(InviteLink.shareText)) {
                            Text("Share link")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(Color(hex: "#FB6F52")))
                        }
                    }
                }
                verifyStatus
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.06)))
        .task(id: vm.verifyChallengeId) {
            // Poll the aggregate match summary while the results screen lives.
            guard vm.verifyChallengeId != nil else { return }
            while !Task.isCancelled {
                await vm.pollVerify()
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }

    @ViewBuilder
    private var verifyStatus: some View {
        let summary = vm.verifySummary
        if summary == nil || (summary?.responses ?? 0) == 0 {
            Label("Waiting for \(vm.who) to swipe — updates live.", systemImage: "hourglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#FFF3C4").opacity(0.5)))
        } else if summary?.matched == true {
            Text("🎯 Confirmed match — \(summary?.by ?? vm.who) swiped right on your pick without knowing it was the ask. Buy it.")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.ink)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#D1E7D4")))
        } else {
            let label = summary?.label
            let line = label == "love"
                ? "No direct hit, but their taste runs hot for it — strong buy signal."
                : label == "like"
                    ? "They didn't pick it directly, but everything they liked sits close to it."
                    : "They passed it by — their swipes point somewhere else."
            Text("\(summary?.responses ?? 1) response in · \(line)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#FFF3C4").opacity(0.5)))
        }
    }
}

// MARK: - Inputs

private struct QuestionTitle: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }
}

private struct ChipGrid: View {
    let chips: [ConsultChip]
    let selected: [String]
    var multi = false
    let tap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            ForEach(chips) { chip in
                let isOn = selected.contains(chip.key)
                Button {
                    tap(chip.key)
                } label: {
                    HStack(spacing: 8) {
                        Text(chip.emoji)
                        Text(chip.label)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if multi && isOn {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(hex: "#FB6F52"))
                                .font(.system(size: 15))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isOn ? Color(hex: "#FFE3DA") : .white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isOn ? Color(hex: "#FB6F52") : Color.black.opacity(0.08), lineWidth: 1.5)
                    )
                }
            }
        }
    }
}

private struct NameInput: View {
    @ObservedObject var vm: ConsultViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Their name", text: $vm.theirName)
                .font(.system(size: 16, design: .rounded))
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08)))
                .submitLabel(.next)
                .onSubmit { vm.phase = .occasion }
            HStack {
                Button("Rather not say") { vm.theirName = ""; vm.phase = .occasion }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if !vm.theirName.trimmingCharacters(in: .whitespaces).isEmpty {
                    PrimaryButton("Next →", compact: true) { vm.phase = .occasion }
                }
            }
        }
    }
}

private struct BudgetInput: View {
    @ObservedObject var vm: ConsultViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                ForEach(ConsultMeta.budgets, id: \.self) { amount in
                    Button {
                        vm.budget = amount
                        vm.phase = .worlds
                    } label: {
                        Text("Under $\(Int(amount))")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 1.5))
                    }
                }
            }
            HStack(spacing: 10) {
                TextField("Or type it — e.g. 80", text: $vm.budgetText)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .font(.system(size: 15, design: .rounded))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.08)))
                if let n = Double(vm.budgetText.trimmingCharacters(in: .whitespaces)), n > 0 {
                    PrimaryButton("Set", compact: true) {
                        vm.budget = n
                        vm.phase = .worlds
                    }
                }
            }
            Button {
                vm.budget = nil
                vm.phase = .worlds
            } label: {
                Text("No budget — just find the gift")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#FB6F52"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#FFE3DA").opacity(0.6)))
            }
        }
    }
}

private struct PrimaryButton: View {
    let title: String
    var compact = false
    let action: () -> Void

    init(_ title: String, compact: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.compact = compact
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 14 : 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: compact ? nil : .infinity)
                .padding(.horizontal, compact ? 18 : 24)
                .padding(.vertical, compact ? 10 : 15)
                .background(Capsule().fill(Color(hex: "#FB6F52")))
        }
    }
}
