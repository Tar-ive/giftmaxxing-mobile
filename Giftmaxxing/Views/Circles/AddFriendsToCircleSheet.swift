import SwiftUI

// Add friends who are ALREADY on Giftmaxxing straight into a circle — the
// WhatsApp-community / Discord model. The share link stays for people without
// the app; this is the one-tap path for people you're already connected to.
// They get a push and the circle appears in their app (server-side membership).
struct AddFriendsToCircleSheet: View {
    let circleId: String
    let circleName: String
    /// Names already seated in this circle — used to mark who is already in.
    let existingMemberNames: Set<String>
    let existingLinkedUserIds: Set<String>
    var onAdded: () -> Void

    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var friends = FriendsStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var addingId: String?
    @State private var addedIds: Set<String> = []
    @State private var failedId: String?

    private var addable: [Friendship] {
        friends.friends.filter { $0.status == "accepted" }
    }

    var body: some View {
        NavigationStack {
            Group {
                if addable.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(addable) { friend in
                                row(friend)
                            }
                        } footer: {
                            Text("They'll get a notification and \(circleName) shows up in their app right away.")
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color.cream)
            .navigationTitle("Add friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if !addedIds.isEmpty { onAdded() }
                        dismiss()
                    }
                }
            }
            .task {
                await friends.refresh(userId: authManager.userId)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No friends yet")
                .font(.displaySmall)
            Text("Connect with people on Giftmaxxing first, then add them here in one tap.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cream)
    }

    private func row(_ friend: Friendship) -> some View {
        let name = friend.name ?? friend.friendId
        let alreadyIn = existingLinkedUserIds.contains(friend.friendId)
            || existingMemberNames.contains(name.lowercased())
        let isAdded = addedIds.contains(friend.friendId)

        return HStack(spacing: 12) {
            AvatarView(name: name, grad: .coral, size: 40, imageUrl: friend.imageUrl)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                if let handle = friend.handle, !handle.isEmpty {
                    Text("@\(handle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)

            if alreadyIn || isAdded {
                Label(isAdded ? "Added" : "In circle", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.success)
            } else if addingId == friend.friendId {
                ProgressView()
            } else {
                Button("Add") {
                    Task { await add(friend, name: name) }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.vertical, 4)
        .alert(
            "Couldn't add them",
            isPresented: Binding(
                get: { failedId == friend.friendId },
                set: { if !$0 { failedId = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again.")
        }
    }

    private func add(_ friend: Friendship, name: String) async {
        addingId = friend.friendId
        defer { addingId = nil }
        do {
            try await APIClient.shared.addCircleMember(
                circleId: circleId,
                userId: friend.friendId,
                name: name,
                byUserId: authManager.userId,
                byName: authManager.displayName
            )
            addedIds.insert(friend.friendId)
        } catch {
            failedId = friend.friendId
        }
    }
}
