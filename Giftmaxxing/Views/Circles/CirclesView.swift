import SwiftUI
import SwiftData
import GiftmaxxingCore
import GiftmaxxingRecommendation
import GiftmaxxingNetworking
import GiftmaxxingDesignSystem

// Circles — your people, their dates, and gifting together. ONE hub:
//   • Circles — shared family/friend groups (server-backed): members add
//     name + birthday via the share link, occasions live with the group
//     (CircleDetailView). The circle IS the gift calendar.
//   • Coming up — a Luma-style vertical timeline of every future moment
//     (your dates + every joined circle's birthdays and occasions), grouped
//     by month, with add-a-date and local reminders (EventsViewModel +
//     ReminderScheduler).
//   • Group gifts — the swipe-to-converge campaigns (GroupGiftViews).
//   • Pools & challenges — the other social plays, one card each.
//
// Layout note: PoolsView and ChallengeView own their NavigationStacks (they
// were standalone destinations before), so they present as sheets here rather
// than pushes — no nested-stack double toolbars.
struct CirclesView: View {
    // Iconography follows the active design variant — see DebugSessionManager.
    private var circleIcons: DesignVariant.CircleIconSet { DebugSessionManager.active.circleIcons }

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var groupGifts = GroupGiftStore.shared
    @ObservedObject private var circleStore = CircleStore.shared
    @StateObject private var eventsModel = EventsViewModel()
    @Environment(\.modelContext) private var modelContext
    @State private var showPools = false
    @State private var showFriends = false
    @State private var showChallenge = false
    @State private var showCreateCircle = false
    @State private var showAddEvent = false
    @State private var showJoinByLink = false
    // DMs moved here from the Home header — Circles is where your people are.
    @State private var showMessages = false
    @State private var showActivity = false
    @State private var activityCount = 0
    @State private var openCircleId: String?
    @State private var openEvent: GiftEvent?
    @State private var openPool: Pool?
    @State private var circleMoments: [TimelineMoment] = []
    // Circle members with birthdays — feeds the birthday-challenge journey.
    @State private var circleBirthdayPeople: [BirthdayChallengeJourney.Person] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Swipe decks friends sent you, waiting to be answered.
                    // (Lived on the Swipe tab before the social layer moved
                    // behind the Circles invite.)
                    ChallengeInviteRail()
                        .padding(.horizontal, -16)

                    // Upcoming celebrations, not a month grid. Gifting dates
                    // are sparse and usually months out, so a 31-day calendar
                    // was ~28 empty cells around two dots — and it had to jump
                    // to July 2027 to show anything at all.
                    UpcomingCelebrationsRail(
                        moments: timelineMoments,
                        onSelect: { moment in
                            switch moment.kind {
                            case .personal(let event): openEvent = event
                            case .circle(let circleId): openCircleId = circleId
                            }
                        },
                        onAddDate: { showAddEvent = true }
                    )
                    .padding(.horizontal, -16) // the rail owns its gutters

                    GiftStreakCard()

                    circlesSection

                    // In-flight group-gift campaigns, as fundraiser cards with
                    // the actual goal metrics. These used to sit on Home; they
                    // belong beside the people they're for.
                    ActiveGroupPoolsSection(
                        onOpenPool: { openPool = $0 },
                        onChat: { _ in showMessages = true }
                    )

                    groupGiftsSection

                    // The other two social plays, one card each.
                    Text("MORE WAYS TO GIFT TOGETHER")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    FeatureCard(
                        icon: "person.2.fill",
                        title: "Friends",
                        subtitle: "Connect & message"
                    ) { showFriends = true }

                    FeatureCard(
                        icon: "banknote.fill",
                        title: "Gift pools",
                        subtitle: "Chip in together"
                    ) { showPools = true }

                    FeatureCard(
                        icon: "paperplane.fill",
                        title: "Gift challenge",
                        subtitle: "Learn a friend's taste"
                    ) { showChallenge = true }
                }
                .padding(16)
                // Clearance for the floating tab bar — without it the last
                // rows (the circle-link door, feature cards) scroll UNDER the
                // bar and can't be tapped.
                .padding(.bottom, 88)
            }
            .background(Color.surface)
            .navigationTitle("Circles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showAddEvent = true }) {
                        Image(systemName: circleIcons.addEvent)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.coral)
                    }
                    .accessibilityLabel("Add a date")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showMessages = true }) {
                        Image(systemName: circleIcons.messages)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.coral)
                    }
                    .accessibilityLabel("Messages")
                }
                // Activity moved off Home's top bar. Every notification this
                // app sends is social and event-driven — someone pledged,
                // someone added to a board, someone's date is close — so it
                // belongs with the people it's about, not beside a search box.
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showActivity = true }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.coral)
                            if activityCount > 0 {
                                Text("\(min(activityCount, 9))")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.onPrimary)
                                    .frame(width: 14, height: 14)
                                    .background(Color.coral, in: Circle())
                                    .offset(x: 7, y: -6)
                            }
                        }
                    }
                    .accessibilityLabel("Activity and invites")
                }
            }
            .sheet(isPresented: $showMessages) {
                NavigationStack { MessagesView() }
            }
            .sheet(isPresented: $showActivity) {
                NavigationStack {
                    NotificationsView()
                        .onDisappear { Task { await refreshActivityBadge() } }
                }
            }
            .task { await refreshActivityBadge() }
            .onChange(of: appState.pendingActivity) { _, pending in
                guard pending else { return }
                showActivity = true
                appState.pendingActivity = false
            }
            .sheet(item: $openPool) { pool in
                PoolDetailView(poolId: pool.id)
            }
            // A message push (or any openMessages() intent) lands here.
            .onChange(of: appState.pendingMessages) { _, pending in
                guard pending else { return }
                showMessages = true
                appState.pendingMessages = false
            }
            .sheet(isPresented: $showPools) { PoolsView() }
            .sheet(isPresented: $showFriends) {
                NavigationStack { FriendsView() }
            }
            // The SAME swipe-challenge flow the Swipe tab uses — wrapped in a
            // stack with an explicit close so the sheet is never a dead end.
            .sheet(isPresented: $showChallenge) {
                NavigationStack { ChallengeView(showsClose: true) }
            }
            .sheet(isPresented: $showCreateCircle) { CreateCircleSheet() }
            .sheet(isPresented: $showAddEvent) {
                AddEventSheet { event in
                    eventsModel.addEvent(event, context: modelContext)
                }
            }
            .sheet(isPresented: $showJoinByLink) {
                JoinCircleByLinkSheet { circleId in
                    openCircleId = circleId
                }
            }
            // Deep link landing: giftmaxxing://circle/<id> or a pasted link.
            .navigationDestination(item: $openCircleId) { circleId in
                CircleDetailView(circleId: circleId)
            }
            .navigationDestination(item: $openEvent) { event in
                EventDetailView(event: event)
            }
            .onChange(of: appState.pendingCircleId) { _, pending in
                if let pending {
                    openCircleId = pending
                    appState.pendingCircleId = nil
                }
            }
            .task {
                if let pending = appState.pendingCircleId {
                    openCircleId = pending
                    appState.pendingCircleId = nil
                }
                // A message push can land before this view exists, so onChange
                // alone would miss it.
                if appState.pendingMessages {
                    showMessages = true
                    appState.pendingMessages = false
                }
                if eventsModel.events.isEmpty {
                    await eventsModel.loadEvents(context: modelContext)
                }
                // Circles a friend added you to live on the server — pull them
                // in before building the calendar.
                await circleStore.syncFromServer(userId: authManager.userId)
                await loadCircleMoments()
                await resyncBirthdayJourney()
            }
            .onChange(of: circleStore.circles.count) { _, _ in
                Task { await loadCircleMoments() }
            }
            .refreshable {
                await eventsModel.loadEvents(context: modelContext)
                await circleStore.syncFromServer(userId: authManager.userId)
                await loadCircleMoments()
                await resyncBirthdayJourney()
            }
        }
    }

    // ── Coming up: a Luma-style timeline — every future moment, yours and
    // your circles', grouped by month so the future is scrollable ────────────

    /// Incoming friend requests + unseen challenge activity. Moved here from
    /// Home's top bar along with the bell itself.
    private func refreshActivityBadge() async {
        let userId = authManager.userId ?? InteractionQueue.anonymousUserId
        async let pending = try? APIClient.shared.listFriends(userId: userId, status: "pending")
        async let unseen = try? APIClient.shared.fetchConnections(userId: userId, unseenOnly: true)
        let incoming = (await pending ?? []).filter { $0.isPending && ($0.incoming ?? ($0.requestedBy != userId)) }
        activityCount = incoming.count + (await unseen ?? []).count
    }

    private var timelineMoments: [TimelineMoment] {
        var items = eventsModel.upcomingEvents.map { event -> TimelineMoment in
            let date = Self.nextOccurrence(for: event)
            return TimelineMoment(
                id: "personal-\(event.id)",
                emoji: event.eventTypeSymbol,
                title: event.title,
                sourceLabel: event.recipientName.isEmpty || event.title.localizedCaseInsensitiveContains(event.recipientName)
                    ? "your list"
                    : "for \(event.recipientName)",
                hasReminder: event.reminderLeadDays != nil,
                date: date,
                days: Self.days(until: date),
                kind: .personal(event)
            )
        }
        items += circleMoments
        return items.sorted { ($0.days, $0.title) < ($1.days, $1.title) }
    }

    // Birthdays and anniversaries roll forward to their next occurrence, so
    // last week's party doesn't sit at the top as "today" forever.
    private static func nextOccurrence(for event: GiftEvent) -> Date {
        let yearly = event.recurrence == "yearly"
            || event.type == "birthday"
            || event.type == "anniversary"
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var date = calendar.startOfDay(for: event.date)
        while yearly, date < today,
              let bumped = calendar.date(byAdding: .year, value: 1, to: date) {
            date = bumped
        }
        return date
    }

    private static func days(until date: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return max(0, calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0)
    }

    // Every joined circle's member birthdays + occasions, fetched in parallel.
    private func loadCircleMoments() async {
        let saved = circleStore.circles
        guard !saved.isEmpty else {
            circleMoments = []
            return
        }
        var collected: [TimelineMoment] = []
        var birthdayPeople: [BirthdayChallengeJourney.Person] = []
        await withTaskGroup(
            of: ([TimelineMoment], [BirthdayChallengeJourney.Person]).self
        ) { group in
            for circle in saved {
                group.addTask {
                    guard let data = try? await APIClient.shared.fetchCircle(circleId: circle.circleId) else {
                        return ([], [])
                    }
                    let moments = CircleMoment.build(from: data).map { moment in
                        TimelineMoment(
                            id: "\(circle.circleId)-\(moment.id)",
                            emoji: moment.emoji,
                            title: moment.turning.map { "\(moment.title) · turning \($0)" } ?? moment.title,
                            sourceLabel: "\(data.circle.name) circle",
                            hasReminder: false,
                            date: moment.date,
                            days: moment.days,
                            kind: .circle(circleId: circle.circleId)
                        )
                    }
                    // Members with birthdays feed the swipe-challenge journey.
                    let people = (data.members ?? []).compactMap { member -> BirthdayChallengeJourney.Person? in
                        guard let ymd = member.birthday,
                              let next = BirthdayChallengeJourney.nextOccurrence(ofYMD: ymd)
                        else { return nil }
                        return BirthdayChallengeJourney.Person(
                            key: "cm-\(member.memberId)",
                            name: member.name,
                            birthday: next
                        )
                    }
                    return (moments, people)
                }
            }
            for await (items, people) in group {
                collected += items
                birthdayPeople += people
            }
        }
        circleMoments = collected
        circleBirthdayPeople = birthdayPeople
    }

    // Re-derive the birthday → swipe-challenge notification journey from
    // everything this screen knows: personal birthday events, circle member
    // birthdays, sent-challenge memory, and completed-but-unseen responses.
    private func resyncBirthdayJourney() async {
        var people: [BirthdayChallengeJourney.Person] = []
        var seenNames = Set<String>()

        for event in eventsModel.upcomingEvents where event.type == "birthday" {
            let name = event.recipientName.isEmpty ? event.title : event.recipientName
            guard !name.isEmpty, seenNames.insert(name.lowercased()).inserted else { continue }
            people.append(BirthdayChallengeJourney.Person(
                key: "evt-\(event.id)",
                name: name,
                birthday: Self.nextOccurrence(for: event)
            ))
        }
        for person in circleBirthdayPeople where seenNames.insert(person.name.lowercased()).inserted {
            people.append(person)
        }

        let sent = BirthdayChallengeJourney.sentChallengeNames()
        var connections: [SoftConnectionItem] = []
        if let userId = authManager.userId {
            connections = (try? await APIClient.shared.fetchConnections(userId: userId)) ?? []
        }
        for index in people.indices {
            let nameKey = people[index].name.lowercased()
            let matches = connections.filter { $0.guestName.lowercased() == nameKey }
            people[index].challengeSent = sent.contains(nameKey) || !matches.isEmpty
            people[index].completedUnseen = matches.contains {
                ($0.totalSwipes ?? 0) > 0 && $0.seen != true
            }
        }

        await BirthdayChallengeJourney.resync(people: people)
    }

    private var circlesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR CIRCLES")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showCreateCircle = true
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.coral)
                }
            }
            .padding(.top, 4)

            if circleStore.circles.isEmpty {
                Button {
                    showCreateCircle = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: circleIcons.circle).foregroundStyle(Color.coral)
                            .font(.system(size: 26))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start a circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ink)
                            Text("One link, everyone's birthdays.")
                                .font(.captionMedium)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            } else {
                ForEach(circleStore.circles) { circle in
                    NavigationLink {
                        CircleDetailView(circleId: circle.circleId)
                    } label: {
                        HStack(spacing: 12) {
                            Text(circle.emoji ?? "🎁")
                                .font(.system(size: 22))
                                .frame(width: 44, height: 44)
                                .background(Color.cream)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(circle.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.ink)
                                Text(circle.joinedAs.map { "you're in as \($0)" } ?? "tap to see whose moment is next")
                                    .font(.captionMedium)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.captionMedium)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Someone texted you a circle link? Paste it here — same landing
            // the web /circle/<id> page gives new arrivals.
            Button {
                showJoinByLink = true
            } label: {
                Label("Got a circle link? Open it here", systemImage: "link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 2)
        }
    }

    // ── Group gifts: active campaigns + start one ────────────────────────────

    @ViewBuilder
    private var groupGiftsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Collaborative boards: friends co-curate a deck, everyone votes
            // by swiping, the group tally picks the winner, and the pool
            // splits the cost. In-flight campaigns live on Home's gifting
            // tray (stories-style bubbles) — Circles keeps the starting point.
            Text("COLLABORATIVE BOARDS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            Text("Curate together, vote by swiping, split the cost.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            NavigationLink(destination: GroupGiftCreateView()) {
                HStack {
                    Spacer()
                    Image(systemName: circleIcons.circle)
                    Text("Start a collaborative board").font(.labelBold)
                    Spacer()
                }
                .padding(.vertical, 15)
                .background(Color.coral)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
        }
    }
}

// The gift streak — consecutive months with at least one thoughtful action
// (a note written, a board shared, a pool started). Volume doesn't move it;
// showing up for your people does.
struct GiftStreakCard: View {
    @ObservedObject private var thoughtfulness = ThoughtfulnessStore.shared
    private var circleIcons: DesignVariant.CircleIconSet { DebugSessionManager.active.circleIcons }

    var body: some View {
        let streak = thoughtfulness.monthlyStreak
        HStack(spacing: 12) {
            Image(systemName: circleIcons.streak)
                .font(.system(size: 22))
                .foregroundStyle(streak > 0 ? Color.coral : Color.inkSecondary)
                .frame(width: 44, height: 44)
                .background(streak > 0 ? Color.coralSoft : Color.cream)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(streak > 0
                     ? "\(streak)-month gift streak"
                     : "Start your gift streak")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.ink)
                Text(streak > 0
                     ? "\(thoughtfulness.points) Thoughtfulness Points"
                     : "One thoughtful act a month keeps it alive.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// Paste a shared circle link (or bare cir_… id) to open that circle — the
// join card on the circle page takes it from there.
private struct JoinCircleByLinkSheet: View {
    var onOpen: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Paste the link from your group chat — it looks like giftmaxxing…/circle/cir_…")
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)

                TextField("https://…/circle/cir_…", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.captionMedium)
                        .foregroundStyle(.red)
                }

                Button {
                    if let circleId = CircleStore.circleId(fromText: text) {
                        dismiss()
                        onOpen(circleId)
                    } else {
                        errorMessage = "That doesn't look like a circle link — it should contain \"cir_…\"."
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Open the circle").font(.labelBold)
                        Spacer()
                    }
                    .padding(.vertical, 13)
                    .background(Color.coral)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .padding(16)
            .background(Color.surface)
            .navigationTitle("Open a circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// One row of the Coming up timeline — a personal date or a circle moment,
// unified so the future reads as a single scrollable feed.
struct TimelineMoment: Identifiable {
    enum Kind {
        case personal(GiftEvent)
        case circle(circleId: String)
    }

    let id: String
    let emoji: String
    let title: String
    let sourceLabel: String
    let hasReminder: Bool
    let date: Date
    let days: Int
    let kind: Kind

    /// Same person, same day. One human's birthday is ONE moment even when they
    /// sit in three of your circles — the list was printing a row per circle,
    /// so "Saksham's birthday · turning 23" appeared twice in a three-row list.
    var identityKey: String {
        let day = Int(date.timeIntervalSince1970 / 86_400)
        return "\(title.lowercased())#\(day)"
    }
}

extension Array where Element == TimelineMoment {
    /// Collapse duplicates of the same person+day, keeping the first and
    /// rewriting the subtitle to name every circle it came from.
    func dedupedByPerson() -> [TimelineMoment] {
        var order: [String] = []
        var grouped: [String: [TimelineMoment]] = [:]
        for moment in self {
            let key = moment.identityKey
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(moment)
        }
        return order.compactMap { key -> TimelineMoment? in
            guard let group = grouped[key], let first = group.first else { return nil }
            guard group.count > 1 else { return first }
            // Distinct labels only — the same circle twice is still one circle.
            var seen = Set<String>()
            let labels = group.map(\.sourceLabel).filter { seen.insert($0).inserted }
            let joined = labels.count <= 2
                ? labels.joined(separator: " · ")
                : "\(labels.count) circles"
            return TimelineMoment(
                id: first.id,
                emoji: first.emoji,
                title: first.title,
                sourceLabel: joined,
                hasReminder: group.contains(where: \.hasReminder),
                date: first.date,
                days: first.days,
                kind: first.kind
            )
        }
    }
}

// Compact row for an active group gift (mirrors GroupGiftViews' private row).
private struct CircleRow: View {
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
                    .font(.captionMedium)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.captionMedium)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct FeatureCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.coral)
                    .frame(width: 36, height: 36)
                    .background(Color.coral.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text(subtitle)
                        .font(.captionMedium)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.captionMedium)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
