import SwiftUI

// One circle — the group's shared gift calendar (web /circle/<id> parity).
// Members + their birthdays and the circle's occasions live server-side under
// the circle partition; anyone with the link can add theirs from any device.
// Every moment row leads somewhere: start a group gift for that person.
struct CircleDetailView: View {
    let circleId: String

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = CircleStore.shared
    @ObservedObject private var friendsStore = FriendsStore.shared
    @State private var data: CircleDataResponse?
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var showAddOccasion = false
    @State private var showAddBirthday = false
    @State private var claimBusy = false
    @State private var claimed = false
    @State private var openDmThreadId: String?
    @State private var showDm = false
    @State private var memberStatuses: [String: String] = [:]
    @State private var challengeName: String?
    @State private var showChallenge = false

    private var myCircle: MyCircle? {
        store.circles.first { $0.circleId == circleId }
    }

    // Member birthdays + shared occasions as one countdown (web upcomingMoments).
    private var moments: [CircleMoment] {
        guard let data else { return [] }
        return CircleMoment.build(from: data)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let data {
                    header(data)
                    if myCircle?.joinedAs == nil {
                        JoinCard(circleId: circleId, circle: data.circle) {
                            Task { await refresh() }
                        }
                    }
                    momentsSection
                    membersSection(data)
                    occasionsSection(data)
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(40)
                } else if loadFailed {
                    VStack(spacing: 8) {
                        Text("This circle doesn't exist (anymore)")
                            .font(.displaySmall)
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.center)
                        Text("Double-check the link, or ask whoever shared it to send a fresh one.")
                            .font(.bodyMedium)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                }
            }
            .padding(16)
        }
        .background(Color.surface)
        .navigationTitle(data?.circle.name ?? myCircle?.name ?? "Circle")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
        .sheet(isPresented: $showAddOccasion, onDismiss: { Task { await refresh() } }) {
            AddCircleOccasionSheet(circleId: circleId, addedBy: myCircle?.joinedAs)
        }
        .sheet(isPresented: $showAddBirthday, onDismiss: { Task { await refresh() } }) {
            AddBirthdaySheet(circleId: circleId, prefillName: myCircle?.joinedAs)
        }
        .navigationDestination(isPresented: $showDm) {
            if let openDmThreadId {
                FriendDmThreadView(threadId: openDmThreadId)
                    .environmentObject(authManager)
                    .environmentObject(appState)
            }
        }
        .sheet(isPresented: $showChallenge) {
            NavigationStack {
                ChallengeView(showsClose: true, prefillTheirName: challengeName ?? "")
            }
            .environmentObject(appState)
        }
        .onAppear {
            AnalyticsEngine.shared.trackScreenView(screen: "circle_detail")
        }
    }

    // ── Sections ─────────────────────────────────────────────────────────────

    @ViewBuilder
    private func header(_ data: CircleDataResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(data.circle.emoji ?? "🎁")
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.circle.name)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.ink)
                    let count = data.members?.count ?? 0
                    Text("\(count) \(count == 1 ? "member" : "members") · a shared calendar of gift moments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // The share link IS the invite: family adds birthdays in the
            // browser, no account, no install.
            HStack(spacing: 8) {
                if let url = CircleStore.shareURL(circleId: circleId) {
                    ShareLink(
                        item: url,
                        message: Text("Join our \"\(data.circle.name)\" gift circle — add your birthday so nobody misses it 🎁")
                    ) {
                        HStack {
                            Spacer()
                            Image(systemName: "paperplane.fill")
                            Text("Invite the group").font(.labelBold)
                            Spacer()
                        }
                        .padding(.vertical, 13)
                        .background(Color.coral)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    }
                }
                if myCircle?.joinedAs != nil {
                    Button {
                        showAddBirthday = true
                    } label: {
                        Text("Edit mine")
                            .font(.labelBold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .background(Color.cream)
                            .foregroundStyle(Color.ink)
                            .clipShape(Capsule())
                    }
                }
                if let joinedAs = myCircle?.joinedAs,
                   let userId = authManager.userId,
                   !mySeatLinked(userId: userId),
                   !claimed {
                    Button {
                        Task { await claimSeat(joinedAs: joinedAs, userId: userId) }
                    } label: {
                        Text(claimBusy ? "Linking…" : "Link my account")
                            .font(.labelBold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .background(Color.ink)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .disabled(claimBusy)
                }
            }
        }
    }

    private func mySeatLinked(userId: String) -> Bool {
        let members = data?.members ?? []
        if members.contains(where: { $0.linkedUserId == userId }) { return true }
        if let joinedAs = myCircle?.joinedAs,
           friendsStore.localClaim(circleId: circleId, memberName: joinedAs) == userId {
            return true
        }
        return false
    }

    private func claimSeat(joinedAs: String, userId: String) async {
        claimBusy = true
        defer { claimBusy = false }
        let ok = await friendsStore.claimCircleSeat(
            circleId: circleId,
            userId: userId,
            memberName: joinedAs
        )
        if ok {
            claimed = true
            await refresh()
        }
    }

    // ── Moments (placeholder to keep structure; existing momentsSection below) ─
    // (momentsSection / membersSection continue below)

    private func linkedUserId(for member: CircleDataResponse.CircleMember) -> String? {
        if let id = member.linkedUserId { return id }
        return friendsStore.localClaim(circleId: circleId, memberName: member.name)
    }

    @ViewBuilder
    private var momentsSection: some View {
        // "Up next" hero — the single closest moment gets the spotlight
        // (web parity), the rest queue up as a countdown list underneath.
        if let next = moments.first {
            VStack(spacing: 8) {
                Text("UP NEXT")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.coral)
                Text(next.emoji)
                    .font(.system(size: 40))
                Text(next.title)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                Text(next.countdownPhrase + (next.turning.map { " — turning \($0)" } ?? ""))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                NavigationLink {
                    GroupGiftCreateView(
                        prefillRecipient: next.who ?? "",
                        prefillOccasion: next.occasionId
                    )
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gift.fill")
                        Text(next.who.map { "Find \($0) a gift" } ?? "Find a gift")
                    }
                    .font(.labelBold)
                    .foregroundStyle(Color.cream)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.ink)
                    .clipShape(Capsule())
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(Color.coralSoft.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.coral.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }

        if moments.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                Text("COMING UP")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)

                ForEach(moments.dropFirst().prefix(8)) { moment in
                    NavigationLink {
                        GroupGiftCreateView(
                            prefillRecipient: moment.who ?? "",
                            prefillOccasion: moment.occasionId
                        )
                    } label: {
                        MomentRow(moment: moment)
                    }
                    .buttonStyle(.plain)
                }

                Text("Tap a moment to rally the circle around a gift.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func membersSection(_ data: CircleDataResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("WHO'S IN")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showAddBirthday = true
                } label: {
                    Label(myCircle?.joinedAs == nil ? "Add yours" : "Edit yours", systemImage: "birthday.cake")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.coral)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array((data.members ?? []).enumerated()), id: \.element.id) { index, member in
                    if index > 0 { Divider().padding(.leading, 56) }
                    memberRow(member)
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .task { await refreshMemberStatuses(data.members ?? []) }
        }
    }

    @ViewBuilder
    private func memberRow(_ member: CircleDataResponse.CircleMember) -> some View {
        let isMe = myCircle?.joinedAs.map { $0.lowercased() == member.name.lowercased() } == true
        let linkedId = linkedUserId(for: member)
        let canConnect = authManager.userId != nil
            && linkedId != nil
            && linkedId != authManager.userId
            && !isMe

        HStack(alignment: .top, spacing: 12) {
            AvatarView(name: member.name, grad: Self.gradFor(member.name), size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(member.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    if isMe {
                        Text("(you)")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(birthdayLabel(member) + (linkedId != nil ? " · on Giftmaxxing" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if canConnect, let linkedId, let myId = authManager.userId {
                    let status = memberStatuses[linkedId] ?? "none"
                    HStack(spacing: 6) {
                        if status == "accepted" {
                            Button("Message") {
                                Task {
                                    if let tid = await friendsStore.openDm(userId: myId, otherUserId: linkedId) {
                                        openDmThreadId = tid
                                        showDm = true
                                    }
                                }
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.ink)
                            .clipShape(Capsule())

                            Button("Challenge") {
                                challengeName = member.linkedName ?? member.name
                                showChallenge = true
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.coral)
                            .clipShape(Capsule())
                        } else if status == "pending" {
                            Text("Request sent")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        } else if status == "incoming" {
                            Button("Accept") {
                                Task {
                                    await friendsStore.acceptFriend(userId: myId, fromUserId: linkedId)
                                    await refreshMemberStatuses(data?.members ?? [])
                                }
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.coral)
                            .clipShape(Capsule())
                        } else {
                            Button("Add friend") {
                                Task {
                                    await friendsStore.requestFriend(
                                        fromUserId: myId,
                                        toUserId: linkedId,
                                        circleId: circleId,
                                        toName: member.linkedName ?? member.name,
                                        toHandle: member.linkedHandle
                                    )
                                    await refreshMemberStatuses(data?.members ?? [])
                                }
                            }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.coral)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer()
            if member.role == "creator" {
                Text("started it")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.cream)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func refreshMemberStatuses(_ members: [CircleDataResponse.CircleMember]) async {
        guard let myId = authManager.userId else { return }
        var next: [String: String] = [:]
        for member in members {
            guard let linked = linkedUserId(for: member), linked != myId else { continue }
            next[linked] = await friendsStore.status(userId: myId, otherId: linked)
        }
        memberStatuses = next
    }

    // Same trick as the web page's gradFor(): hash the name onto the avatar
    // palette so every member gets a stable, distinct color.
    static func gradFor(_ name: String) -> GradientStyle {
        let styles = GradientStyle.allCases
        var h = 0
        for u in name.unicodeScalars {
            h = (h &* 31 &+ Int(u.value)) & 0x7fffffff
        }
        return styles[h % styles.count]
    }

    @ViewBuilder
    private func occasionsSection(_ data: CircleDataResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SHARED OCCASIONS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showAddOccasion = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.coral)
                }
            }

            let events = data.events ?? []
            if events.isEmpty {
                Text("Anniversaries, graduations, the family reunion — add the dates the whole circle should gift around.")
                    .font(.bodyMedium)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { Divider().padding(.leading, 16) }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.ink)
                                HStack(spacing: 6) {
                                    Text(event.date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let by = event.addedBy, !by.isEmpty {
                                        Text("· added by \(by)")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task {
                                    _ = try? await APIClient.shared.deleteCircleEvent(
                                        circleId: circleId,
                                        eventId: event.eventId
                                    )
                                    await refresh()
                                }
                            } label: {
                                Label("Remove occasion", systemImage: "trash")
                            }
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button(role: .destructive) {
                store.forget(circleId)
            } label: {
                Text("Leave this circle on this device")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
    }

    private func birthdayLabel(_ member: CircleDataResponse.CircleMember) -> String {
        guard let birthday = member.birthday,
              let next = CircleMoment.nextOccurrence(ofYMD: birthday) else {
            return "no birthday yet"
        }
        let days = CircleMoment.daysUntil(next)
        if days == 0 { return "🎂 TODAY!" }
        return "🎂 \(CircleMoment.monthDayString(next)) · in \(days) \(days == 1 ? "day" : "days")"
    }

    private func refresh() async {
        isLoading = data == nil
        defer { isLoading = false }
        do {
            let fresh = try await APIClient.shared.fetchCircle(circleId: circleId)
            data = fresh
            loadFailed = false
            // Keep the local name/emoji in step with the server.
            if myCircle != nil {
                store.remember(
                    circleId: circleId,
                    name: fresh.circle.name,
                    emoji: fresh.circle.emoji,
                    joinedAs: myCircle?.joinedAs
                )
            }
        } catch {
            loadFailed = true
        }
    }
}

// ── Moments (birthdays + occasions as one countdown) ─────────────────────────

struct CircleMoment: Identifiable {
    let id: String
    let title: String
    let who: String?
    let emoji: String
    let date: Date
    let days: Int
    let turning: Int? // age on the next birthday, when the year looks real
    let occasionId: String // GroupGiftCreateView occasion id

    var countdownPhrase: String {
        if days == 0 { return "It's today! 🎉" }
        if days == 1 { return "Tomorrow!" }
        return "In \(days) days"
    }

    static func build(from data: CircleDataResponse, now: Date = Date()) -> [CircleMoment] {
        var out: [CircleMoment] = []
        for member in data.members ?? [] {
            guard let birthday = member.birthday,
                  let next = nextOccurrence(ofYMD: birthday, from: now) else { continue }
            out.append(CircleMoment(
                id: "bday-\(member.memberId)",
                title: "\(member.name)'s birthday",
                who: member.name,
                emoji: "🎂",
                date: next,
                days: daysUntil(next, from: now),
                turning: turningAge(birthday: birthday, from: now),
                occasionId: "birthday"
            ))
        }
        for event in data.events ?? [] {
            guard let next = nextOccurrence(ofYMD: event.date, from: now) else { continue }
            out.append(CircleMoment(
                id: event.eventId,
                title: event.title,
                who: event.forName,
                emoji: emoji(forType: event.type ?? "occasion"),
                date: next,
                days: daysUntil(next, from: now),
                turning: nil,
                occasionId: occasionId(forType: event.type ?? "occasion")
            ))
        }
        return out.sorted { $0.days < $1.days }
    }

    // Age they'll turn on their next birthday — only when the year looks like
    // a real birth year (web turningAge parity; members can enter Jan 1 of any
    // year to keep their age private).
    static func turningAge(birthday: String, from: Date = Date()) -> Int? {
        let parts = birthday.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]) else { return nil }
        let currentYear = Calendar.current.component(.year, from: from)
        guard year >= 1900, year <= currentYear else { return nil }
        guard let next = nextOccurrence(ofYMD: birthday, from: from) else { return nil }
        return Calendar.current.component(.year, from: next) - year
    }

    static func monthDayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMd")
        return formatter.string(from: date)
    }

    // Next occurrence of the MM-DD on or after today (annual roll-forward,
    // mirrors web/lib/circles.ts nextOccurrence).
    static func nextOccurrence(ofYMD ymd: String, from: Date = Date()) -> Date? {
        let parts = ymd.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: from)
        let today = calendar.startOfDay(for: from)
        var components = DateComponents(year: year, month: month, day: day)
        guard var candidate = calendar.date(from: components) else { return nil }
        if candidate < today {
            components.year = year + 1
            guard let nextYear = calendar.date(from: components) else { return nil }
            candidate = nextYear
        }
        return candidate
    }

    static func daysUntil(_ date: Date, from: Date = Date()) -> Int {
        let calendar = Calendar.current
        let a = calendar.startOfDay(for: from)
        let b = calendar.startOfDay(for: date)
        return max(0, calendar.dateComponents([.day], from: a, to: b).day ?? 0)
    }

    private static func emoji(forType type: String) -> String {
        switch type {
        case "birthday": return "🎂"
        case "anniversary": return "💝"
        case "wedding": return "💒"
        case "graduation": return "🎓"
        case "holiday": return "🎄"
        case "baby-shower", "baby_shower": return "🍼"
        case "farewell": return "👋"
        default: return "✨"
        }
    }

    private static func occasionId(forType type: String) -> String {
        // Map circle event types onto GroupGiftCreateView's occasion ids.
        switch type {
        case "birthday", "anniversary", "wedding", "graduation", "holiday", "farewell":
            return type
        case "baby-shower", "baby_shower":
            return "baby-shower"
        default:
            return "other"
        }
    }
}

private struct MomentRow: View {
    let moment: CircleMoment

    var body: some View {
        HStack(spacing: 12) {
            Text(moment.emoji)
                .font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(Color.coralSoft)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                (Text(moment.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                 + Text(moment.turning.map { " — turning \($0)" } ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary))
                    .lineLimit(1)
                Text(CircleMoment.monthDayString(moment.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Web-parity pill: coral inside two weeks, quiet otherwise.
            Text(moment.days == 0 ? "Today!" : moment.days == 1 ? "Tomorrow" : "\(moment.days)d")
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(moment.days <= 14 ? Color.coral : Color.cream)
                .foregroundStyle(moment.days <= 14 ? .white : Color.ink.opacity(0.6))
                .clipShape(Capsule())
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// The 15-second ask for new arrivals (web JoinCard parity): name + birthday,
// no account. Shows inline whenever this device hasn't joined the circle yet —
// including when someone lands here from a shared link.
private struct JoinCard: View {
    let circleId: String
    let circle: CircleDataResponse.CircleMeta
    var onJoined: () -> Void

    @State private var name = ""
    @State private var includeBirthday = true
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add yourself to the circle")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.ink)
            Text("Your name and birthday — that's it. If you're signed in, we'll link your account so circle mates can friend and gift you.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)

            Toggle("Include my birthday", isOn: $includeBirthday)
                .font(.system(size: 14))
            if includeBirthday {
                DatePicker("Birthday", selection: $birthday, displayedComponents: .date)
                    .font(.system(size: 14))
                Text("The year is only used for the \"turning N\" countdown — pick Jan 1 of any year if you'd rather not share it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await join() }
            } label: {
                HStack {
                    Spacer()
                    if isJoining {
                        ProgressView().tint(.white)
                    } else {
                        Text("I'm in 🎁").font(.labelBold)
                    }
                    Spacer()
                }
                .padding(.vertical, 13)
                .background(Color.coral)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isJoining)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }

    private func join() async {
        isJoining = true
        defer { isJoining = false }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let userId = AuthManager.shared.userId
        do {
            _ = try await APIClient.shared.joinCircle(
                circleId: circleId,
                name: trimmed,
                birthday: includeBirthday ? FlexibleDate.ymdString(from: birthday) : nil,
                userId: userId
            )
            CircleStore.shared.remember(
                circleId: circleId,
                name: circle.name,
                emoji: circle.emoji,
                joinedAs: trimmed
            )
            if let userId {
                _ = await FriendsStore.shared.claimCircleSeat(
                    circleId: circleId,
                    userId: userId,
                    memberName: trimmed
                )
            }
            AnalyticsEngine.shared.trackScreenView(screen: "circle_joined")
            onJoined()
        } catch {
            errorMessage = "Couldn't join right now — try again in a moment."
        }
    }
}

// ── Sheets ───────────────────────────────────────────────────────────────────

// Add a shared occasion to the circle (anniversaries, reunions, …).
struct AddCircleOccasionSheet: View {
    let circleId: String
    var addedBy: String?

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var type = "anniversary"
    @State private var forName = ""
    @State private var date = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let types: [(id: String, label: String)] = [
        ("anniversary", "💝 Anniversary"), ("wedding", "💒 Wedding"),
        ("graduation", "🎓 Graduation"), ("holiday", "🎄 Holiday"),
        ("baby-shower", "🍼 Baby shower"), ("farewell", "👋 Farewell"),
        ("occasion", "✨ Something else"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("What's the occasion?") {
                    TextField("Title (e.g. Mom & Dad's anniversary)", text: $title)
                    Picker("Type", selection: $type) {
                        ForEach(Self.types, id: \.id) { t in
                            Text(t.label).tag(t.id)
                        }
                    }
                    TextField("Who's it for? (optional)", text: $forName)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Section {
                    Button(action: { Task { await save() } }) {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Add to the circle")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                        .background(Color.coral)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Shared occasion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await APIClient.shared.addCircleEvent(
                circleId: circleId,
                title: title.trimmingCharacters(in: .whitespaces),
                date: FlexibleDate.ymdString(from: date),
                type: type,
                forName: forName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : forName.trimmingCharacters(in: .whitespaces),
                addedBy: addedBy
            )
            dismiss()
        } catch {
            errorMessage = "Couldn't save — try again in a moment."
        }
    }
}

// Add (or update) your own name + birthday in the circle — join upserts by
// name, so re-saving from the same link just updates the date.
struct AddBirthdaySheet: View {
    let circleId: String
    var prefillName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("You, in this circle") {
                    TextField("Your name", text: $name)
                    DatePicker("Birthday", selection: $birthday, displayedComponents: .date)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Section {
                    Button(action: { Task { await save() } }) {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Save my birthday")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                        .background(Color.coral)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Your birthday")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if name.isEmpty, let prefillName { name = prefillName }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let userId = AuthManager.shared.userId
        do {
            _ = try await APIClient.shared.joinCircle(
                circleId: circleId,
                name: trimmed,
                birthday: FlexibleDate.ymdString(from: birthday),
                userId: userId
            )
            CircleStore.shared.remember(
                circleId: circleId,
                name: CircleStore.shared.circles.first { $0.circleId == circleId }?.name ?? "Circle",
                emoji: CircleStore.shared.circles.first { $0.circleId == circleId }?.emoji,
                joinedAs: trimmed
            )
            if let userId {
                _ = await FriendsStore.shared.claimCircleSeat(
                    circleId: circleId,
                    userId: userId,
                    memberName: trimmed
                )
            }
            dismiss()
        } catch {
            errorMessage = "Couldn't save — try again in a moment."
        }
    }
}

// Start a new circle: name it, say who you are, share the link.
struct CreateCircleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var name = ""
    @State private var emoji = "🎁"
    @State private var yourName = ""
    @State private var includeBirthday = false
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var created: MyCircle?

    private static let emojis = ["🎁", "👨‍👩‍👧‍👦", "❤️", "🎉", "🏡", "🐣", "🎄", "✨"]

    var body: some View {
        NavigationStack {
            if let created {
                successView(created)
            } else {
                formView
            }
        }
    }

    @ViewBuilder
    private var formView: some View {
        Form {
            Section("Name the circle") {
                TextField("e.g. Sharma Family, College crew", text: $name)
                Picker("Emoji", selection: $emoji) {
                    ForEach(Self.emojis, id: \.self) { e in
                        Text(e).tag(e)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("You") {
                TextField("Your name", text: $yourName)
                Toggle("Add my birthday too", isOn: $includeBirthday)
                if includeBirthday {
                    DatePicker("Birthday", selection: $birthday, displayedComponents: .date)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Section {
                Button(action: { Task { await create() } }) {
                    HStack {
                        Spacer()
                        if isCreating {
                            ProgressView().tint(.white)
                        } else {
                            Text("Create the circle")
                                .font(.system(size: 16, weight: .bold))
                        }
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 12)
                    .background(Color.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text("You'll get a link — share it in the group chat and everyone adds their birthday. No accounts needed.")
            }
        }
        .navigationTitle("New circle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear {
            if yourName.isEmpty, let userName = appState.currentUser?.name {
                yourName = userName
            }
        }
    }

    @ViewBuilder
    private func successView(_ circle: MyCircle) -> some View {
        VStack(spacing: 18) {
            Text(circle.emoji ?? "🎁")
                .font(.system(size: 56))
            Text("\(circle.name) is live")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.ink)
            Text("Now share the link — everyone who opens it can drop their name + birthday straight into the circle.")
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let url = CircleStore.shareURL(circleId: circle.circleId) {
                ShareLink(
                    item: url,
                    message: Text("Join our circle on Giftmaxxing — drop your birthday so nobody misses it 🎂")
                ) {
                    HStack {
                        Spacer()
                        Image(systemName: "paperplane.fill")
                        Text("Share the invite").font(.labelBold)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(Color.coral)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 24)
            }

            Button("Done") { dismiss() }
                .font(.labelBold)
                .foregroundStyle(Color.coral)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surface)
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedYou = yourName.trimmingCharacters(in: .whitespaces)
        do {
            let res = try await APIClient.shared.createCircle(
                name: trimmedName,
                emoji: emoji,
                creatorName: trimmedYou.isEmpty ? nil : trimmedYou,
                creatorBirthday: includeBirthday ? FlexibleDate.ymdString(from: birthday) : nil
            )
            CircleStore.shared.remember(
                circleId: res.circleId,
                name: trimmedName,
                emoji: emoji,
                joinedAs: trimmedYou.isEmpty ? nil : trimmedYou
            )
            created = CircleStore.shared.circles.first { $0.circleId == res.circleId }
            AnalyticsEngine.shared.trackScreenView(screen: "circle_created")
        } catch {
            errorMessage = "Couldn't create the circle — try again in a moment."
        }
    }
}
