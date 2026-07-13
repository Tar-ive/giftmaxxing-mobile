import SwiftUI

// The Home bell. One inbox for everything that used to be invisible:
//   • friend requests (accept / decline inline)
//   • swipe activity — completed challenges & swipe-list responses (unseen
//     soft-profile connections, marked seen on view)
//   • upcoming friend/circle occasions (next 14 days)
// plus the enable-push card when notification permission isn't granted yet,
// so this screen doubles as the permission prompt surface.
struct NotificationsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var pushManager: PushManager

    @State private var requests: [Friendship] = []
    @State private var activity: [SoftConnectionItem] = []
    @State private var events: [UpcomingEvent] = []
    @State private var isLoading = true
    @State private var actedRequestIds: Set<String> = []

    private var userId: String {
        authManager.userId ?? InteractionQueue.anonymousUserId
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if pushManager.permissionStatus != .authorized {
                    enablePushCard
                }

                if isLoading && requests.isEmpty && activity.isEmpty && events.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("Checking what's new…")
                            .font(.bodyMedium)
                            .padding(.top, 40)
                        Spacer()
                    }
                } else if requests.isEmpty && activity.isEmpty && events.isEmpty {
                    emptyState
                } else {
                    if !requests.isEmpty {
                        section("Friend requests", icon: "person.crop.circle.badge.plus") {
                            ForEach(requests) { request in
                                friendRequestRow(request)
                            }
                        }
                    }
                    if !activity.isEmpty {
                        section("Swipe activity", icon: "rectangle.stack.badge.person.crop") {
                            ForEach(activity) { conn in
                                activityRow(conn)
                            }
                        }
                    }
                    if !events.isEmpty {
                        section("Coming up", icon: "calendar.badge.clock") {
                            ForEach(events) { event in
                                eventRow(event)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color.surface)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Sections

    @ViewBuilder
    private func section(_ title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.coral)
                Text(title)
                    .font(.displaySmall)
                    .foregroundStyle(Color.ink)
            }
            content()
        }
    }

    private var enablePushCard: some View {
        Button {
            Task { await pushManager.requestPermission() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Turn on notifications")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Friend requests, swipe results, and gift-date reminders — the moment they happen.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(14)
            .background(Color.coral)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text("You're all caught up")
                .font(.displaySmall)
                .foregroundStyle(Color.ink)
            Text("Friend requests, completed swipe challenges, and upcoming occasions land here.")
                .font(.bodyMedium)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 24)
    }

    // MARK: - Rows

    private func friendRequestRow(_ request: Friendship) -> some View {
        HStack(spacing: 12) {
            AvatarView(name: request.name ?? "?", grad: .lilac, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.name ?? "Someone")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ink)
                Text("wants to be gift friends")
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if actedRequestIds.contains(request.friendId) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.coral)
            } else {
                Button("Accept") {
                    Task { await accept(request) }
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.coral)
                .clipShape(Capsule())
                .buttonStyle(.plain)

                Button {
                    Task { await decline(request) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.cream)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.cream.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func activityRow(_ conn: SoftConnectionItem) -> some View {
        HStack(spacing: 12) {
            AvatarView(name: conn.guestName, grad: .sky, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(conn.guestName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ink)
                Text(activityLine(conn))
                    .font(.bodySmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if conn.seen == false {
                Circle()
                    .fill(Color.coral)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(12)
        .background(Color.cream.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func activityLine(_ conn: SoftConnectionItem) -> String {
        let swipes = conn.totalSwipes ?? 0
        let yes = conn.yesCount ?? 0
        var line = swipes > 0
            ? "finished your swipe challenge — \(yes)/\(swipes) yes"
            : "shared their gift taste with you"
        if let vibes = conn.vibes, !vibes.isEmpty {
            line += " · into \(vibes.prefix(2).joined(separator: ", "))"
        }
        return line
    }

    private func eventRow(_ event: UpcomingEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "gift.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.coral)
                .frame(width: 40, height: 40)
                .background(Color.coralSoft)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(eventTitle(event))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ink)
                if let days = event.daysUntil {
                    Text(days == 0 ? "Today — last call for a gift" : "in \(days) day\(days == 1 ? "" : "s")")
                        .font(.bodySmall)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color.cream.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func eventTitle(_ event: UpcomingEvent) -> String {
        let who = event.recipientName ?? event.recipient?.name ?? "Someone"
        let type = (event.type ?? event.title ?? "occasion").replacingOccurrences(of: "-", with: " ")
        return "\(who)'s \(type)"
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let pending = try? APIClient.shared.listFriends(userId: userId, status: "pending")
        async let unseen = try? APIClient.shared.fetchConnections(userId: userId, unseenOnly: true)
        async let upcoming = try? APIClient.shared.fetchUpcomingEvents(userId: userId, withinDays: 14)
        // Incoming requests only — outgoing pendings aren't actionable here.
        requests = (await pending ?? []).filter { $0.isPending && ($0.incoming ?? ($0.requestedBy != userId)) }
        activity = (await unseen) ?? []
        events = (await upcoming) ?? []
        // Viewing IS acknowledging: clear the unseen flags (and the bell badge).
        if activity.contains(where: { $0.seen == false }) {
            await APIClient.shared.markConnectionsSeen(userId: userId)
        }
    }

    private func accept(_ request: Friendship) async {
        actedRequestIds.insert(request.friendId)
        _ = try? await APIClient.shared.acceptFriend(userId: userId, fromUserId: request.friendId)
    }

    private func decline(_ request: Friendship) async {
        requests.removeAll { $0.friendId == request.friendId }
        _ = try? await APIClient.shared.removeFriend(userId: userId, friendId: request.friendId)
    }
}
