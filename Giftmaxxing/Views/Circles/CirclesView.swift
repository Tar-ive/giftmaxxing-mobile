import SwiftUI
import SwiftData

// Circles — your people, their dates, and gifting together. ONE hub:
//   • Circles — shared family/friend groups (server-backed): members add
//     name + birthday via the share link, occasions live with the group
//     (CircleDetailView). The circle IS the gift calendar.
//   • Coming up — every date you track (yours + logged occasions), with
//     add-a-date and local reminders (EventsViewModel + ReminderScheduler).
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
    @State private var showChallenge = false
    @State private var showCreateCircle = false
    @State private var showAddEvent = false
    @State private var showJoinByLink = false
    @State private var openCircleId: String?
    @State private var calendarMonth = Date()
    @State private var selectedCalendarDay: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Why this tab exists, in one line.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your people, their moments")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.ink)
                        Text("Keep every birthday and occasion in one place — then gift together when the day comes.")
                            .font(.bodyMedium)
                            .foregroundStyle(.secondary)
                    }

                    calendarSection
                    comingUpSection
                    circlesSection
                    groupGiftsSection

                    // The other two social plays, one card each.
                    Text("MORE WAYS TO GIFT TOGETHER")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    FeatureCard(
                        icon: "banknote.fill",
                        title: "Gift pools",
                        subtitle: "Chip in on something big — everyone contributes what they can."
                    ) { showPools = true }

                    FeatureCard(
                        icon: "paperplane.fill",
                        title: "Gift challenge",
                        subtitle: "Send a swipe deck to learn a friend's taste — no account needed on their end."
                    ) { showChallenge = true }
                }
                .padding(16)
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
                await ReminderScheduler.requestPermissionIfNeeded()
            }
            .refreshable {
                await eventsModel.loadEvents(context: modelContext)
            }
        }
    }

    // ── Calendar: the month at a glance, dots where moments live ───────────

    @ViewBuilder
    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CALENDAR")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            MonthCalendarCard(
                month: $calendarMonth,
                selectedDay: $selectedCalendarDay,
                events: eventsModel.events
            )

            // Tapping a dotted day lists that day's moments right below.
            if let day = selectedCalendarDay {
                let dayEvents = eventsModel.events.filter {
                    Calendar.current.isDate($0.date, inSameDayAs: day)
                }
                ForEach(dayEvents) { event in
                    NavigationLink {
                        EventDetailView(event: event)
                    } label: {
                        UpcomingDateRow(event: event)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // ── Coming up: every tracked date, closest first ─────────────────────────

    @ViewBuilder
    private var comingUpSection: some View {
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

            if eventsModel.upcomingEvents.isEmpty {
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
                            Text("Add a date and we'll remind you in time to actually get the gift.")
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
                ForEach(eventsModel.upcomingEvents.prefix(4)) { event in
                    NavigationLink {
                        EventDetailView(event: event)
                    } label: {
                        UpcomingDateRow(event: event)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            eventsModel.deleteEvent(event, context: modelContext)
                        } label: {
                            Label("Delete event", systemImage: "trash")
                        }
                    }
                }

                if eventsModel.upcomingEvents.count > 4 {
                    NavigationLink {
                        EventsView()
                            .toolbar(.hidden, for: .tabBar)
                    } label: {
                        Text("All \(eventsModel.upcomingEvents.count) dates")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.coral)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.coralSoft)
                            .clipShape(Capsule())
                    }
                }
            }
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
                            Text("One link for the family group chat — everyone drops their birthday, the circle becomes your gift calendar.")
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
            // In-flight campaigns now live on Home's gifting tray (stories-
            // style bubbles) — Circles keeps only the starting point.
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
        }
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

// Compact countdown row for the Coming up strip (denser than EventCard).
private struct UpcomingDateRow: View {
    let event: GiftEvent

    private var urgencyColor: Color {
        let days = event.daysUntil
        if days <= 3 { return .red }
        if days <= 7 { return .orange }
        if days <= 14 { return Color.coral }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(event.eventTypeIcon)
                .font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(Color.cream)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(event.dateString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if event.reminderLeadDays != nil {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.coral)
                    }
                }
            }

            Spacer()

            VStack(spacing: 0) {
                Text(event.daysUntil == 0 ? "🎉" : "\(event.daysUntil)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(urgencyColor)
                if event.daysUntil > 0 {
                    Text(event.daysUntil == 1 ? "day" : "days")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// ── Month calendar: dots where moments live ──────────────────────────────────
// A dependency-free month grid. Coral ring = today, coral dot = a tracked
// date lands there; tapping a dotted day lists its events under the card.
struct MonthCalendarCard: View {
    @Binding var month: Date
    @Binding var selectedDay: Date?
    let events: [GiftEvent]

    private var calendar: Calendar { Calendar.current }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: month)
    }

    private var weekdaySymbols: [String] {
        // Rotate so the row starts on the user's first weekday (Sun vs Mon).
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // The month laid out as grid slots: nil = leading blank before day 1.
    private var daySlots: [Date?] {
        guard
            let interval = calendar.dateInterval(of: .month, for: month),
            let dayCount = calendar.range(of: .day, in: .month, for: month)?.count
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var slots = [Date?](repeating: nil, count: leading)
        for day in 0..<dayCount {
            slots.append(calendar.date(byAdding: .day, value: day, to: interval.start))
        }
        return slots
    }

    private func hasEvents(on day: Date) -> Bool {
        events.contains { calendar.isDate($0.date, inSameDayAs: day) }
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: month) {
            month = next
            selectedDay = nil
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.coral)
                        .frame(width: 30, height: 30)
                }
                Spacer()
                Text(monthTitle)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink)
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.coral)
                        .frame(width: 30, height: 30)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(daySlots.enumerated()), id: \.offset) { _, slot in
                    if let day = slot {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let dotted = hasEvents(on: day)

        Button {
            selectedDay = isSelected ? nil : (dotted ? day : nil)
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 13, weight: isToday || isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : isToday ? Color.coral : Color.ink)
                Circle()
                    .fill(dotted ? (isSelected ? Color.white : Color.coral) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? Color.coral : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isToday && !isSelected ? Color.coral : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
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
