import SwiftUI
import GiftmaxxingCore

// Swipe lists a friend sent you IN the app. Before this, an invite only
// existed as a link in a DM — easy to miss and easy to lose. Now it waits at
// the top of Circles (the invite-only social hub) until you answer it.
struct ChallengeInviteRail: View {
    @EnvironmentObject private var authManager: AuthManager

    @State private var invites: [ChallengeInvite] = []
    @State private var openChallenge: ChallengeRef?

    var body: some View {
        Group {
            if !invites.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WAITING ON YOU")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.inkTertiary)
                        .tracking(0.5)
                        .padding(.horizontal, 20)

                    ForEach(invites) { invite in
                        Button {
                            openChallenge = ChallengeRef(id: invite.challengeId)
                        } label: {
                            row(invite)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 12)
            }
        }
        .task(id: authManager.userId) { await load() }
        .sheet(item: $openChallenge, onDismiss: { Task { await load() } }) { ref in
            ChallengeSwipeView(challengeId: ref.id)
                .environmentObject(authManager)
        }
    }

    private func row(_ invite: ChallengeInvite) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.coralSoft)
                Image(systemName: "gift.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.coral)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(invite.fromName.map { "\($0) needs your help" } ?? "A gift challenge for you")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text(subtitle(invite))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text("Swipe")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.coral)
        }
        .padding(12)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous)
                .stroke(Color.coral.opacity(0.35), lineWidth: 1)
        )
    }

    private func subtitle(_ invite: ChallengeInvite) -> String {
        var parts: [String] = []
        if let size = invite.deckSize, size > 0 { parts.append("\(size) ideas") }
        if let occasion = invite.occasion, !occasion.isEmpty { parts.append(occasion) }
        parts.append("a few taps")
        return parts.joined(separator: " · ")
    }

    private func load() async {
        guard let userId = authManager.userId else {
            invites = []
            return
        }
        invites = (try? await APIClient.shared.fetchChallengeInvites(userId: userId)) ?? []
    }
}
