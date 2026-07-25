import SwiftUI
import SwiftData

// Swipe → "People": the challenge hub. Every person you gift for, in one
// list, split by what you can DO right now:
//   • Their swipes are in → open the results (what they said yes to, their
//     vibes, product-vs-service split) and go buy.
//   • Waiting on them → nudge/re-share the challenge you already sent.
//   • Birthday coming, nothing sent → share a challenge (auto-created).
// No logged people yet → point at Circles, where dates get logged.
struct PeopleHubView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.modelContext) private var modelContext

    @StateObject private var eventsModel = EventsViewModel()
    @State private var connections: [SoftConnectionItem] = []
    @State private var circleBirthdays: [CircleBirthday] = []
    @State private var isLoading = false

    struct CircleBirthday {
        let name: String
        let daysUntil: Int
    }
    @State private var sharingWith: SharePrefill?
    @State private var viewingResults: SoftConnectionItem?

    private struct SharePrefill: Identifiable {
        let id = UUID()
        let name: String
    }

    private struct Person: Identifiable {
        let name: String
        let daysUntil: Int?      // nil when no logged date
        let occasionIcon: String
        let connection: SoftConnectionItem?

        var id: String { name.lowercased() }
        var hasResults: Bool { (connection?.totalSwipes ?? 0) > 0 }
        var isUnseen: Bool { hasResults && connection?.seen != true }
    }

    // Everyone worth acting on: people with upcoming dates, plus anyone who
    // already swiped a challenge (even without a logged date).
    private var people: [Person] {
        var byName: [String: Person] = [:]

        // Circle members with birthdays count as people you gift for — the
        // hub was personal-events-only, so a user whose dates all live in a
        // circle saw an empty screen. You don't gift yourself here.
        let myName = (authManager.displayName ?? "").lowercased()
        for member in circleBirthdays where member.name.lowercased() != myName {
            byName[member.name.lowercased()] = Person(
                name: member.name,
                daysUntil: member.daysUntil,
                occasionIcon: "🎂",
                connection: match(name: member.name)
            )
        }

        for event in eventsModel.upcomingEvents {
            let name = event.recipientName.isEmpty ? event.title : event.recipientName
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            // Keep the soonest date per person.
            if let existing = byName[key], (existing.daysUntil ?? .max) <= event.daysUntil { continue }
            byName[key] = Person(
                name: name,
                daysUntil: event.daysUntil,
                occasionIcon: event.eventTypeIcon,
                connection: match(name: name)
            )
        }
        for connection in connections where (connection.totalSwipes ?? 0) > 0 {
            let key = connection.guestName.lowercased()
            guard !connection.guestName.isEmpty, byName[key] == nil else { continue }
            byName[key] = Person(
                name: connection.guestName,
                daysUntil: nil,
                occasionIcon: "🎁",
                connection: connection
            )
        }

        // Results first (they're actionable), then by how soon the date is.
        return byName.values.sorted { a, b in
            if a.hasResults != b.hasResults { return a.hasResults }
            return (a.daysUntil ?? .max) < (b.daysUntil ?? .max)
        }
    }

    private func match(name: String) -> SoftConnectionItem? {
        let key = name.lowercased()
        return connections
            .filter { $0.guestName.lowercased() == key }
            .max { ($0.totalSwipes ?? 0) < ($1.totalSwipes ?? 0) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if isLoading && people.isEmpty {
                    ProgressView()
                        .padding(.top, 60)
                } else if people.isEmpty {
                    emptyState
                } else {
                    ForEach(people) { person in
                        personRow(person)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $sharingWith) { prefill in
            NavigationStack {
                ChallengeView(
                    showsClose: true,
                    prefillTheirName: prefill.name,
                    autoCreate: true
                )
            }
        }
        .sheet(item: $viewingResults) { connection in
            ChallengeResultsSheet(connection: connection)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No people yet")
                .font(.displaySmall)
            Text("Log the dates you gift for — birthdays, graduations — and they show up here to swipe for.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                appState.selectedTab = .circles
            } label: {
                Text("Log an event in Circles")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 4)
        }
        .padding(.top, 50)
        .padding(.horizontal, 24)
    }

    private func personRow(_ person: Person) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    AvatarView(name: person.name, grad: .coral, size: 46)
                    if person.isUnseen {
                        Circle()
                            .fill(Color.coral)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(Color.cream, lineWidth: 2))
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(person.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text(statusLine(person))
                        .font(.caption)
                        .foregroundStyle(person.hasResults ? Color.coral : Color.inkSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let days = person.daysUntil {
                    VStack(spacing: 0) {
                        Text("\(days)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(days == 1 ? "day" : "days")
                            .font(.caption2)
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .foregroundStyle(days <= 3 ? Color.coral : Color.ink)
                }
            }

            if person.hasResults, let connection = person.connection {
                Button {
                    viewingResults = connection
                } label: {
                    Label("See their swipe results", systemImage: "chart.bar.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Button {
                    sharingWith = SharePrefill(name: person.name)
                } label: {
                    Label(
                        person.connection == nil ? "Share a swipe challenge" : "Nudge them again",
                        systemImage: "paperplane.fill"
                    )
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(12)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
    }

    private func statusLine(_ person: Person) -> String {
        if let connection = person.connection, let total = connection.totalSwipes, total > 0 {
            let yes = connection.yesCount ?? 0
            return "\(yes) of \(total) swipes were a yes"
        }
        if person.connection != nil { return "Challenge sent — waiting on their swipes" }
        if let days = person.daysUntil, days <= 14 {
            return "Coming up — you don't know their taste yet"
        }
        return "No swipe challenge yet"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        await eventsModel.loadEvents(context: modelContext)
        if let userId = authManager.userId {
            connections = (try? await APIClient.shared.fetchConnections(userId: userId)) ?? []
        }
        await loadCircleBirthdays()
    }

    private func loadCircleBirthdays() async {
        let circles = CircleStore.shared.circles
        guard !circles.isEmpty else {
            circleBirthdays = []
            return
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var collected: [CircleBirthday] = []

        await withTaskGroup(of: [CircleBirthday].self) { group in
            for circle in circles {
                group.addTask {
                    guard let data = try? await APIClient.shared.fetchCircle(circleId: circle.circleId) else {
                        return []
                    }
                    return (data.members ?? []).compactMap { member in
                        guard let ymd = member.birthday,
                              let next = BirthdayChallengeJourney.nextOccurrence(ofYMD: ymd)
                        else { return nil }
                        let days = calendar.dateComponents([.day], from: today, to: next).day ?? 0
                        return CircleBirthday(name: member.name, daysUntil: max(0, days))
                    }
                }
            }
            for await items in group { collected += items }
        }
        circleBirthdays = collected
    }
}

// What their swipes actually said — the payoff screen the reminders promise.
struct ChallengeResultsSheet: View {
    let connection: SoftConnectionItem

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    private var yesRate: Int? {
        guard let total = connection.totalSwipes, total > 0 else { return nil }
        return Int((Double(connection.yesCount ?? 0) / Double(total) * 100).rounded())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 14) {
                        AvatarView(name: connection.guestName, grad: .coral, size: 60)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(connection.guestName)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.ink)
                            if let total = connection.totalSwipes, total > 0 {
                                Text("\(connection.yesCount ?? 0) of \(total) swipes were a yes")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.inkSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    if let rate = yesRate {
                        statCard(
                            title: "How picky they are",
                            value: "\(rate)%",
                            caption: rate >= 60
                                ? "Easy to please — most ideas landed."
                                : rate >= 30
                                    ? "Selective — the yeses really mean something."
                                    : "Very particular. Stick to exactly what they liked."
                        )
                    }

                    if let split = connection.giftTypeSplit {
                        giftTypeCard(split)
                    }

                    if let vibes = connection.vibes, !vibes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("What they're drawn to")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.ink)
                            FlowChips(items: Array(vibes.prefix(8)))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
                    }

                    Button {
                        dismiss()
                        appState.selectedTab = .feed
                    } label: {
                        Text("Find gifts they'll love")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(16)
            }
            .background(Color.cream)
            .navigationTitle("Their swipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            // Opening the results clears the "unseen" state the birthday
            // reminders key off.
            if let userId = authManager.userId, connection.seen != true {
                await APIClient.shared.markConnectionsSeen(
                    userId: userId,
                    connectionIds: [connection.connectionId]
                )
            }
        }
    }

    private func statCard(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.ink)
            Text(value)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.coral)
                .monospacedDigit()
            Text(caption)
                .font(.system(size: 13))
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
    }

    private func giftTypeCard(_ split: GiftTypeSplit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Things or experiences?")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.ink)
            Text(splitCopy(split))
                .font(.system(size: 13))
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
    }

    private func splitCopy(_ split: GiftTypeSplit) -> String {
        let product = split.productYesRate ?? 0
        let service = split.serviceYesRate ?? 0
        if product > service + 0.15 { return "They lean toward physical gifts they can unwrap." }
        if service > product + 0.15 { return "They lean toward experiences and subscriptions." }
        return "They're happy with either — a thing or an experience."
    }
}

// Simple wrapping chip row for vibe tags.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.coral)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.coralSoft)
                        .clipShape(Capsule())
                }
            }
        }
    }
}
