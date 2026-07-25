import SwiftUI

// Gift Boards a co-giver handed you — "we're both shopping for Mom, here's
// what I've found so far." Accepting copies it into your boards so you can add
// your own ideas, then either of you sends the deck to the recipient.
struct SharedBoardsRail: View {
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var boards = SwipeListStore.shared

    @State private var shares: [SharedBoard] = []
    @State private var accepting: String?

    var body: some View {
        Group {
            if !shares.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SHARED WITH YOU")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.inkTertiary)
                        .tracking(0.5)

                    ForEach(shares) { share in
                        row(share)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .task(id: authManager.userId) { await load() }
    }

    private func row(_ share: SharedBoard) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.coralSoft)
                Image(systemName: "rectangle.stack.badge.person.crop.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.coral)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(share.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text(subtitle(share))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if accepting == share.shareId {
                ProgressView()
            } else {
                Button("Add mine") { Task { await accept(share) } }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(12)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous)
                .stroke(Color.coral.opacity(0.3), lineWidth: 1)
        )
    }

    private func subtitle(_ share: SharedBoard) -> String {
        var parts: [String] = []
        if let from = share.fromName, !from.isEmpty { parts.append("from \(from)") }
        let count = share.posts?.count ?? 0
        if count > 0 { parts.append("\(count) idea\(count == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        guard let userId = authManager.userId else {
            shares = []
            return
        }
        shares = (try? await APIClient.shared.fetchSharedBoards(userId: userId)) ?? []
    }

    private func accept(_ share: SharedBoard) async {
        accepting = share.shareId
        defer { accepting = nil }

        let list = boards.createList(
            name: share.name,
            recipientName: share.recipientName,
            occasion: share.occasion
        )
        for api in share.posts ?? [] {
            let post = await APIClient.shared.post(from: api)
            boards.toggle(post, in: list.id)
        }
        if let userId = authManager.userId {
            await APIClient.shared.acceptSharedBoard(shareId: share.shareId, userId: userId)
        }
        shares.removeAll { $0.shareId == share.shareId }
    }
}
