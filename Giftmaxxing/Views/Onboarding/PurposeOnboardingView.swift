import SwiftUI

// Two decisions, then value. Taste learning belongs in the Swipe tab where the
// action has context; onboarding only establishes who the user shops for and a
// useful price prior before showing community-backed picks.
enum GiftingPrefs {
    private static let personaKey = "onboarding.persona"
    private static let relationshipsKey = "onboarding.relationships"
    private static let budgetKey = "onboarding.budget"
    private static let stylesKey = "onboarding.giftStyles"
    private static let contactRelKey = "onboarding.contactRelationships"
    private static let nameKey = "onboarding.preferredName"
    private static let inviteCountKey = "onboarding.inviteCount"
    private static let recipientSegmentKey = "onboarding.recipientSegment"

    static var preferredName: String? {
        get { UserDefaults.standard.string(forKey: nameKey) }
        set { UserDefaults.standard.set(newValue, forKey: nameKey) }
    }
    static var recipientSegment: String? {
        get { UserDefaults.standard.string(forKey: recipientSegmentKey) }
        set { UserDefaults.standard.set(newValue, forKey: recipientSegmentKey) }
    }
    static var persona: String? {
        get { UserDefaults.standard.string(forKey: personaKey) }
        set { UserDefaults.standard.set(newValue, forKey: personaKey) }
    }
    static var relationships: [String] {
        get { UserDefaults.standard.stringArray(forKey: relationshipsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: relationshipsKey) }
    }
    static var budget: String? {
        get { UserDefaults.standard.string(forKey: budgetKey) }
        set { UserDefaults.standard.set(newValue, forKey: budgetKey) }
    }
    static var giftStyles: [String] {
        get { UserDefaults.standard.stringArray(forKey: stylesKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: stylesKey) }
    }
    static var contactRelationships: [String] {
        get { UserDefaults.standard.stringArray(forKey: contactRelKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: contactRelKey) }
    }
    static var inviteCount: Int {
        get { UserDefaults.standard.integer(forKey: inviteCountKey) }
        set { UserDefaults.standard.set(min(max(newValue, 0), 5), forKey: inviteCountKey) }
    }

    static func clear() {
        [personaKey, relationshipsKey, budgetKey, stylesKey, contactRelKey, nameKey,
         inviteCountKey, recipientSegmentKey].forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}

struct PurposeOnboardingView: View {
    var onDone: () -> Void

    @State private var step = 0
    @State private var preferredName = GiftingPrefs.preferredName ?? ""
    @State private var segment = GiftingPrefs.recipientSegment
    @State private var budget = GiftingPrefs.budget
    @State private var leaderboard: [RecipientLeaderboardItem] = []
    @State private var isLoading = false

    private struct Recipient: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
    }

    private static let recipients = [
        Recipient(id: "women", title: "Her", subtitle: "Women & girls", symbol: "person.fill"),
        Recipient(id: "men", title: "Him", subtitle: "Men & boys", symbol: "figure.stand"),
        Recipient(id: "partner", title: "Partner", subtitle: "Someone special", symbol: "heart.fill"),
        Recipient(id: "kids", title: "Kids", subtitle: "Little people", symbol: "figure.2.and.child.holdinghands"),
        Recipient(id: "friend", title: "Friend", subtitle: "Friends & coworkers", symbol: "person.2.fill"),
        Recipient(id: "anyone", title: "Not sure", subtitle: "Show broad ideas", symbol: "sparkles"),
    ]
    private static let budgets = ["Under $25", "$25–75", "$75–200", "$200+"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? Color.coral : Color.line)
                        .frame(width: index == step ? 28 : 8, height: 7)
                }
                Spacer()
                Text("\(step + 1) of 2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            Group {
                if step == 0 { recipientStep } else { leaderboardStep }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: advance) {
                Text(step == 0 ? "Show me what people love" : "Start exploring")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canContinue ? Color.coral : Color.coral.opacity(0.35), in: Capsule())
            }
            .disabled(!canContinue)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.surface)
        }
        .background(Color.surface.ignoresSafeArea())
        .onAppear { seedScreenshotStateIfNeeded() }
    }

    private var recipientStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                title("Who are you gifting?", "This gives your first recommendations a useful starting point.")

                TextField("What should we call you?", text: $preferredName)
                    .textContentType(.name)
                    .font(.body)
                    .padding()
                    .background(Color.cream, in: RoundedRectangle(cornerRadius: ThemeRadius.md))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Self.recipients) { recipient in
                        Button { segment = recipient.id } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: recipient.symbol)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(segment == recipient.id ? .white : Color.coral)
                                Text(recipient.title).font(.headline)
                                Text(recipient.subtitle).font(.caption).opacity(0.75)
                            }
                            .foregroundStyle(segment == recipient.id ? .white : Color.ink)
                            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                            .padding(12)
                            .background(segment == recipient.id ? Color.coral : Color.cream,
                                        in: RoundedRectangle(cornerRadius: ThemeRadius.lg))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(segment == recipient.id ? .isSelected : [])
                    }
                }

                Text("USUAL BUDGET").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.budgets, id: \.self) { option in
                            Button { budget = option } label: {
                                Text(option)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(budget == option ? .white : Color.ink)
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                    .background(budget == option ? Color.ink : Color.cream, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollClipDisabled()
            }
            .padding(24)
        }
    }

    private var leaderboardStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                title("Popular for \(recipientTitle.lowercased())", "Ranked from recent positive swipes. As more people swipe, this list gets smarter.")

                if isLoading && leaderboard.isEmpty {
                    ProgressView("Checking recent favorites…")
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    ForEach(Array(leaderboard.prefix(6).enumerated()), id: \.element.id) { index, result in
                        HStack(spacing: 14) {
                            Text("\(index + 1)")
                                .font(.title2.weight(.heavy))
                                .foregroundStyle(index < 3 ? Color.coral : Color.inkTertiary)
                                .frame(width: 28)
                            CachedAsyncImage(url: result.post.product.image, width: 220)
                                .aspectRatio(1, contentMode: .fill)
                                .frame(width: 76, height: 76)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.md))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(result.post.product.name).font(.headline).lineLimit(2)
                                Text(result.post.product.brand).font(.caption).foregroundStyle(.secondary)
                                Text(result.voterCount > 0 ? "Loved by \(result.voterCount) people" : "Curated starting pick")
                                    .font(.caption.weight(.semibold)).foregroundStyle(Color.coral)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.cream, in: RoundedRectangle(cornerRadius: ThemeRadius.lg))
                    }
                }

                Label("Keep swiping after setup to teach your own taste—or share a deck so a friend can teach you theirs.", systemImage: "hand.draw.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding()
                    .background(Color.coralSoft, in: RoundedRectangle(cornerRadius: ThemeRadius.md))
            }
            .padding(24)
        }
        .task(id: segment) { await loadLeaderboard() }
    }

    private var canContinue: Bool {
        step == 1 || (!preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && segment != nil)
    }

    private var recipientTitle: String {
        Self.recipients.first(where: { $0.id == segment })?.title ?? "everyone"
    }

    private func title(_ heading: String, _ subheading: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(heading).font(.largeTitle.weight(.heavy)).fontDesign(.rounded).foregroundStyle(Color.ink)
            Text(subheading).font(.body).foregroundStyle(.secondary)
        }
    }

    private func advance() {
        if step == 0 {
            GiftingPrefs.preferredName = preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
            GiftingPrefs.recipientSegment = segment
            GiftingPrefs.relationships = segment.map { [$0] } ?? []
            GiftingPrefs.budget = budget
            PersonalizationStore.genderPref = segment == "women" ? "her" : segment == "men" ? "him" : nil
            step = 1
        } else {
            onDone()
        }
    }

    private func loadLeaderboard() async {
        guard let segment else { return }
        isLoading = true
        leaderboard = (try? await APIClient.shared.fetchRecipientLeaderboard(segment: segment)) ?? fallbackLeaderboard(segment)
        if leaderboard.isEmpty { leaderboard = fallbackLeaderboard("anyone") }
        isLoading = false
    }

    private func fallbackLeaderboard(_ segment: String) -> [RecipientLeaderboardItem] {
        let aliases: [String: [String]] = [
            "women": ["women", "girl", "beauty", "jewelry"],
            "men": ["men", "boy", "tech", "practical"],
            "partner": ["anniversary", "romantic", "partner"],
            "kids": ["kid", "girl", "boy", "creative"],
            "friend": ["friend", "birthday", "under-50"],
        ]
        let terms = aliases[segment] ?? []
        let products = CuratedGiftStore.shared.challengeProducts
        let ranked = products.sorted { left, right in
            let l = terms.filter { "\(left.product.name) \(left.caption) \(left.category ?? "")".lowercased().contains($0) }.count
            let r = terms.filter { "\(right.product.name) \(right.caption) \(right.category ?? "")".lowercased().contains($0) }.count
            return l == r ? left.product.price < right.product.price : l > r
        }
        return ranked.prefix(8).enumerated().map { RecipientLeaderboardItem(rank: $0.offset + 1, voterCount: 0, post: $0.element) }
    }

    private func seedScreenshotStateIfNeeded() {
        #if DEBUG
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "onboardingScreenshotMode") else { return }
        step = min(max(defaults.integer(forKey: "onboardingScreenshotStep"), 0), 1)
        preferredName = "Alex"
        segment = "partner"
        budget = "$25–75"
        if step == 1 { leaderboard = fallbackLeaderboard("partner") }
        #endif
    }
}
