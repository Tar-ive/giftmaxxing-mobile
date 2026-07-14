import SwiftUI

/// Compact group-gift rail on Home — fundraiser-style cards:
/// "For Sarah's birthday", a progress bar, "$X raised", and the faces of
/// everyone who has chipped in (first four + how many more). No goal math on
/// the card — the pool page has the details; the rail sells the momentum.
struct CompactPledgeRail: View {
    @ObservedObject private var pools = PoolsStore.shared
    @ObservedObject private var groupGifts = GroupGiftStore.shared
    var onSelectPool: (Pool) -> Void

    private var items: [GroupGiftCardModel] {
        GroupGiftCardModel.build(pools: pools.pools, gifts: groupGifts.gifts)
    }

    var body: some View {
        // No real group gifts yet → don't render the rail at all (no empty
        // header, no demo cards).
        if items.isEmpty {
            EmptyView()
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Group gifts", systemImage: "person.2.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ink)
                Spacer()
                Text("Swipe to browse")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        GroupGiftPledgeCard(item: item) {
                            onSelectPool(item.pool)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 14)
                .padding(.vertical, 2)
            }
            .scrollTargetBehavior(.viewAligned)
        }
        .padding(.vertical, 8)
        .background(Color.surface)
    }
}

// MARK: - Card model

struct GroupGiftCardModel: Identifiable {
    let id: String
    let pool: Pool
    let recipient: String
    let headline: String

    static func build(pools: [Pool], gifts: [GroupGift]) -> [GroupGiftCardModel] {
        let byPoolId = Dictionary(uniqueKeysWithValues: gifts.compactMap { gift -> (String, GroupGift)? in
            guard let poolId = gift.poolId else { return nil }
            return (poolId, gift)
        })

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

// MARK: - Card

private struct GroupGiftPledgeCard: View {
    let item: GroupGiftCardModel
    let onPledge: () -> Void

    private let width: CGFloat = 190

    private var progress: Double {
        guard item.pool.targetAmount > 0 else { return 0 }
        return min(1, item.pool.currentAmount / item.pool.targetAmount)
    }

    var body: some View {
        Button(action: onPledge) {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.headline)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 40, alignment: .topLeading)

                // Momentum, not math: the bar shows how far along the pool
                // is; the exact goal lives on the pool page.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.cream)
                        Capsule()
                            .fill(Color.coral)
                            .frame(width: max(6, geo.size.width * progress))
                    }
                }
                .frame(height: 6)

                Text("$\(Int(item.pool.currentAmount)) raised")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.ink)

                contributorsRow
            }
            .padding(12)
            .frame(width: width, alignment: .leading)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous)
                    .stroke(Color.line, lineWidth: 1)
            }
            .cardElevation()
        }
        .buttonStyle(.plain)
        .scrollTransition(.animated, axis: .horizontal) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.96)
                .opacity(phase.isIdentity ? 1 : 0.88)
        }
        .accessibilityLabel("\(item.headline), $\(Int(item.pool.currentAmount)) raised, \(item.pool.contributors.count) contributed")
    }

    // Everyone who chipped in — the first four faces + how many more.
    private var contributorsRow: some View {
        let contributors = Array(item.pool.contributors.prefix(4))
        return HStack(spacing: -8) {
            if contributors.isEmpty {
                Text("Be the first to chip in")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.coral)
            }
            ForEach(Array(contributors.enumerated()), id: \.element.id) { index, person in
                AvatarView(name: person.name, grad: person.avatarGrad, size: 26)
                    .overlay(Circle().stroke(Color.surface, lineWidth: 2))
                    .zIndex(Double(contributors.count - index))
            }
            if item.pool.contributors.count > 4 {
                Text("+\(item.pool.contributors.count - 4)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.ink.opacity(0.85))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.surface, lineWidth: 2))
            }
        }
        .frame(height: 26)
    }
}
