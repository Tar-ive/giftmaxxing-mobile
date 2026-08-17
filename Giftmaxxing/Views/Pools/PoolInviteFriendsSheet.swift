import SwiftUI
import GiftmaxxingCore

/// Sends the same canonical pool invite URL through an accepted in-app DM.
/// External recipients use the adjacent system ShareLink instead.
struct PoolInviteFriendsSheet: View {
    let pool: Pool
    let inviterName: String

    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var friends = FriendsStore.shared
    @State private var sentTo: Set<String> = []
    @State private var sendingTo: String?

    private var inviteURL: URL? {
        InviteLink.buildPoolURL(inviterName: inviterName, pool: pool)
    }

    var body: some View {
        NavigationStack {
            List {
                if friends.friends.isEmpty {
                    ContentUnavailableView(
                        "No friends to invite yet",
                        systemImage: "person.2",
                        description: Text("Add friends first, or use Share pool invite for anyone off Giftmaxxing.")
                    )
                } else {
                    ForEach(friends.friends) { friend in
                        HStack {
                            AvatarView(
                                name: friend.name ?? friend.handle ?? "Friend",
                                grad: SocialUsers.grad(for: friend.friendId),
                                size: 38
                            )
                            VStack(alignment: .leading) {
                                Text(friend.name ?? friend.handle ?? "Friend")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Send a pool invite in chat")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if sentTo.contains(friend.friendId) {
                                Label("Sent", systemImage: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.green)
                            } else if sendingTo == friend.friendId {
                                ProgressView()
                            } else {
                                Button("Invite") {
                                    Task { await send(to: friend) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color.coral)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Invite friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await friends.refresh(userId: authManager.userId)
            }
        }
    }

    private func send(to friend: Friendship) async {
        guard let userId = authManager.userId, let inviteURL else { return }
        sendingTo = friend.friendId
        defer { sendingTo = nil }
        guard let threadId = await friends.openDm(userId: userId, otherUserId: friend.friendId) else { return }
        let message = "Chip in for \(pool.title): \(inviteURL.absoluteString)"
        if await friends.sendMessage(
            threadId: threadId,
            userId: userId,
            name: authManager.displayName ?? "A friend",
            text: message
        ) != nil {
            sentTo.insert(friend.friendId)
        }
    }
}
