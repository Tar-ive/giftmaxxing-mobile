import SwiftUI
import SwiftData

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
    @EnvironmentObject private var appState: AppState
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
    @State private var openCircleId: String?
    @State private var circleMoments: [TimelineMoment] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Your people, their moments")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.ink)

                    GiftStreakCard()

                    timelineSection
                    circlesSection
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
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.coral)
                    }
                }
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
                if eventsModel.events.isEmpty {
                    await eventsModel.loadEvents(context: modelContext)
                }
                await loadCircleMoments()
                await ReminderScheduler.requestPermissionIfNeeded()
            }
            .onChange(of: circleStore.circles.count) { _, _ in
                Task { await loadCircleMoments() }
            }
            .refreshable {
                await eventsModel.loadEvents(context: modelContext)
                await loadCircleMoments()
            }
        }
    }

    // ── Coming up: a Luma-style timeline — every future moment, yours and
    // your circles', grouped by month so the future is scrollable ────────────

    private var timelineMoments: [TimelineMoment] {
        var items = eventsModel.upcomingEvents.map { event -> TimelineMoment in
            let date = Self.nextOccurrence(for: event)
            return TimelineMoment(
                id: "personal-\(event.id)",
                emoji: event.eventTypeIcon,
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

    private var timelineMonths: [(id: String, title: String, items: [TimelineMoment])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var out: [(id: String, title: String, items: [TimelineMoment])] = []
        for item in timelineMoments {
            let title = formatter.string(from: item.date)
            if out.last?.id == title {
                out[out.count - 1].items.append(item)
            } else {
                out.append((id: title, title: title, items: [item]))
            }
        }
        return out
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
        await withTaskGroup(of: [TimelineMoment].self) { group in
            for circle in saved {
                group.addTask {
                    guard let data = try? await APIClient.shared.fetchCircle(circleId: circle.circleId) else {
                        return []
                    }
                    return CircleMoment.build(from: data).map { moment in
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
                }
            }
            for await items in group {
                collected += items
            }
        }
        circleMoments = collected
    }

    @ViewBuilder
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("COMING UP")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showAddEvent = true
                } label: {
                    Label("Add a date", systemImage: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.coral)
                }
            }
            .padding(.top, 4)

            if timelineMoments.isEmpty {
                Button {
                    showAddEvent = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.coral)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Never miss a birthday again")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ink)
                            Text("Add a date or join a circle.")
                                .font(.caption)
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
                ForEach(timelineMonths, id: \.id) { month in
                    Text(month.title.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.coral)
                        .padding(.top, 2)

                    ForEach(month.items) { item in
                        timelineRow(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func timelineRow(_ item: TimelineMoment) -> some View {
        switch item.kind {
        case .personal(let event):
            NavigationLink {
                EventDetailView(event: event)
            } label: {
                TimelineMomentRow(item: item)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) {
                    eventsModel.deleteEvent(event, context: modelContext)
                } label: {
                    Label("Delete event", systemImage: "trash")
                }
            }
        case .circle(let circleId):
            NavigationLink {
                CircleDetailView(circleId: circleId)
            } label: {
                TimelineMomentRow(item: item)
            }
            .buttonStyle(.plain)
        }
    }

    // ── Your circles: the shared groups ──────────────────────────────────────

    @ViewBuilder
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
                        Text("👨‍👩‍👧‍👦")
                            .font(.system(size: 26))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Start a circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ink)
                            Text("One link, everyone's birthdays.")
                                .font(.caption)
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
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(Color.white)
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
                    Image(systemName: "person.3.fill")
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

    var body: some View {
        let streak = thoughtfulness.monthlyStreak
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
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
                        .font(.caption)
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
}

// Luma-style event row: date tile on the left, moment + where it comes from
// in the middle, countdown pill on the right.
private struct TimelineMomentRow: View {
    let item: TimelineMoment

    private var urgencyColor: Color {
        if item.days <= 3 { return .red }
        if item.days <= 7 { return .orange }
        if item.days <= 14 { return Color.coral }
        return .secondary
    }

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: item.date))"
    }

    private var weekday: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: item.date).uppercased()
    }

    private var countdown: String {
        if item.days == 0 { return "today 🎉" }
        if item.days == 1 { return "tomorrow" }
        return "in \(item.days)d"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(dayNumber)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(item.days == 0 ? Color.coral : Color.ink)
                Text(weekday)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .background(Color.cream)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(item.emoji)
                        .font(.system(size: 13))
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text(item.sourceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if item.hasReminder {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.coral)
                    }
                }
            }

            Spacer()

            Text(countdown)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(item.days == 0 ? Color.coral : urgencyColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background((item.days == 0 ? Color.coral : urgencyColor).opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.white)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
