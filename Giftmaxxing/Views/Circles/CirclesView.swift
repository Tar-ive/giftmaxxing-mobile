import SwiftUI

// Circles — the social gifting hub, promoted to a first-class tab.
//
// Everything "gift together" lives here instead of being buried in More:
//   • Group gifts — one friend starts a deck, the circle swipes, the tally
//     converges on THE gift, then everyone pledges a share (GroupGiftViews).
//   • Gift pools — chip in on something big (PoolsView).
//   • Gift challenges — the viral "learn a friend's taste" swipe link
//     (ChallengeView), including the concierge's verify-by-swipe decks.
//
// Layout note: PoolsView and ChallengeView own their NavigationStacks (they
// were standalone destinations before), so they present as sheets here rather
// than pushes — no nested-stack double toolbars.
struct CirclesView: View {
    @ObservedObject private var groupGifts = GroupGiftStore.shared
    @State private var showPools = false
    @State private var showChallenge = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Why this tab exists, in one line.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Gift better, together")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.ink)
                        Text("Start a circle around one person — friends swipe, the favorite wins, everyone chips in.")
                            .font(.bodyMedium)
                            .foregroundStyle(.secondary)
                    }

                    // Primary action: start a group gift.
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

                    // Active circles.
                    if !groupGifts.gifts.isEmpty {
                        Text("YOUR CIRCLES")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)

                        ForEach(groupGifts.gifts) { gift in
                            NavigationLink(destination: GroupGiftDetailView(giftId: gift.id)) {
                                CircleRow(gift: gift)
                            }
                            .buttonStyle(.plain)
                        }
                    }

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
            .sheet(isPresented: $showPools) { PoolsView() }
            .sheet(isPresented: $showChallenge) { ChallengeView() }
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
