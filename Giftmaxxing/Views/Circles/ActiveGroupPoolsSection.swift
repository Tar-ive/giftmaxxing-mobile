import SwiftUI

// Active group gifts, as fundraiser-style progress cards.
//
// A group gift is a campaign with a number attached, and the number is the
// thing people come back to check: how close are we, and does it still need me?
// The old rail showed the recipient and a "Pledge" affordance but buried the
// arithmetic, so there was nothing to come back FOR.
//
// Full-width cards rather than a horizontal rail: these are the highest-intent
// items on the screen, and a rail hides everything past the second one.
struct ActiveGroupPoolsSection: View {
    @ObservedObject private var pools = PoolsStore.shared
    @ObservedObject private var groupGifts = GroupGiftStore.shared

    var onOpenPool: (Pool) -> Void
    var onChat: (Pool) -> Void

    private var items: [GroupGiftCardModel] {
        GroupGiftCardModel.build(pools: pools.pools, gifts: groupGifts.gifts)
    }

    var body: some View {
        // Nothing running → render nothing. An empty "Active pools" header is
        // worse than no header.
        if items.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: ThemeSpacing.xs) {
                SectionHeader("Active group gifts")
                ForEach(items.prefix(4)) { item in
                    GroupPoolProgressCard(
                        item: item,
                        onPledge: { onOpenPool(item.pool) },
                        onChat: { onChat(item.pool) }
                    )
                }
            }
        }
    }
}

private struct GroupPoolProgressCard: View {
    let item: GroupGiftCardModel
    var onPledge: () -> Void
    var onChat: () -> Void

    private var pool: Pool { item.pool }
    private var funded: Bool { pool.progressPercent >= 1 }

    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AvatarView(name: item.recipient, grad: .lilac, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.headline)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text(contributorLine)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            // The number, stated plainly. "$140 / $250 raised" is the whole
            // reason to look at this card.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(money(pool.currentAmount))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(funded ? Color.success : Color.ink)
                Text("/ \(money(pool.targetAmount)) raised")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)
                Spacer(minLength: 0)
                Text("\(Int(pool.progressPercent * 100))%")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(funded ? Color.success : Color.coral)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surfaceSunken)
                    Capsule()
                        .fill(funded ? Color.success : Color.coral)
                        .frame(width: max(6, geo.size.width * pool.progressPercent))
                }
            }
            .frame(height: 7)

            HStack(spacing: 8) {
                Button(action: onPledge) {
                    Text(funded ? "View" : "Pledge")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(funded ? Color.success : Color.coral, in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onChat) {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.surfaceSunken, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous)
                .strokeBorder(Color.line, lineWidth: 1)
        }
    }

    private var contributorLine: String {
        let count = pool.contributors.count
        let remaining = max(0, pool.targetAmount - pool.currentAmount)
        if funded { return "Fully funded — \(count) contributed" }
        if count == 0 { return "\(money(remaining)) to go · be the first" }
        return "\(count) contributed · \(money(remaining)) to go"
    }
}

// Moved here with the section that uses it — CompactPledgeRail, its previous
// home, was deleted when Home's group-gift rail moved to Circles.
struct GroupGiftCardModel: Identifiable {
    let id: String
    let pool: Pool
    let recipient: String
    let headline: String

    static func build(pools: [Pool], gifts: [GroupGift]) -> [GroupGiftCardModel] {
        // Two gifts can point at the same pool — uniqueKeysWithValues would
        // trap on that, on the HOME feed.
        let byPoolId = Dictionary(
            gifts.compactMap { gift -> (String, GroupGift)? in
                guard let poolId = gift.poolId else { return nil }
                return (poolId, gift)
            },
            uniquingKeysWith: { _, latest in latest }
        )

        // Only the user's real pools — no demo fallback (it used to show the
        // same fake pools to everyone).
        let source = Array(pools.prefix(8))
        return source.map { pool in
            let gift = byPoolId[pool.id]
            let recipient = gift?.recipient ?? pool.forUser
            let occasion = (gift?.occasion ?? pool.occasion)?.trimmingCharacters(in: .whitespaces)
            let headline: String
            if let occasion, !occasion.isEmpty {
                headline = "For \(recipient)'s \(occasion.lowercased())"
            } else {
                headline = "For \(recipient)"
            }
            return GroupGiftCardModel(
                id: pool.id,
                pool: pool,
                recipient: recipient,
                headline: headline
            )
        }
    }
}
