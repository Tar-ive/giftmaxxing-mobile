import SwiftUI

/// Compact Amazon-style group-gift rail on Home.
///
/// Cards are pools / pledge rounds — not product feed picks. White copy sits
/// behind the recipient portrait (Amazon "text in the back" composition). For
/// now every card uses a known black studio background so white type stays
/// legible; later we'll pick text color from the photo.
struct CompactPledgeRail: View {
    @ObservedObject private var pools = PoolsStore.shared
    @ObservedObject private var groupGifts = GroupGiftStore.shared
    var onSelectPool: (Pool) -> Void

    private var items: [GroupGiftCardModel] {
        GroupGiftCardModel.build(pools: pools.pools, gifts: groupGifts.gifts)
    }

    var body: some View {
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
    let subhead: String
    /// Stable demo portrait URLs known to read well on black (dark studio shots).
    /// Real profiles will replace these once we have recipient photos + dynamic
    /// text-color picking.
    let portraitURL: URL?

    static func build(pools: [Pool], gifts: [GroupGift]) -> [GroupGiftCardModel] {
        let byPoolId = Dictionary(uniqueKeysWithValues: gifts.compactMap { gift -> (String, GroupGift)? in
            guard let poolId = gift.poolId else { return nil }
            return (poolId, gift)
        })

        let source = pools.isEmpty ? Pool.samples : Array(pools.prefix(8))
        return source.enumerated().map { index, pool in
            let gift = byPoolId[pool.id]
            let recipient = gift?.recipient ?? pool.forUser
            let occasion = gift?.occasion ?? pool.occasion
            let amount = Int(pool.targetAmount)
            let headline: String
            if let occasion, !occasion.isEmpty {
                headline = "\(occasion) for \(recipient)"
            } else {
                headline = "Gift for \(recipient)"
            }
            return GroupGiftCardModel(
                id: pool.id,
                pool: pool,
                recipient: recipient,
                headline: headline,
                subhead: "$\(amount) goal · $\(Int(pool.currentAmount)) raised",
                portraitURL: Self.demoPortrait(at: index)
            )
        }
    }

    private static func demoPortrait(at index: Int) -> URL? {
        // Dark / black-studio portrait placeholders so white overlay type works.
        // Swap for real recipient photos once the profile pipeline ships them.
        let urls = [
            "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=600&h=800&fit=crop&q=80",
            "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=600&h=800&fit=crop&q=80",
            "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=600&h=800&fit=crop&q=80",
        ]
        return URL(string: urls[index % urls.count])
    }
}

// MARK: - Card

private struct GroupGiftPledgeCard: View {
    let item: GroupGiftCardModel
    let onPledge: () -> Void

    private let width: CGFloat = 168
    private let height: CGFloat = 228

    var body: some View {
        Button(action: onPledge) {
            ZStack(alignment: .bottom) {
                // Black studio plate — known-good for white type until we
                // compute contrast from real photos.
                Color.black

                // Layer 1 (back): headline copy, Amazon-style.
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.headline)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("$\(Int(item.pool.targetAmount))")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))

                    Text(item.pool.product?.name ?? item.subhead)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 64)

                // Layer 2 (front): recipient portrait overlapping the copy.
                HStack {
                    Spacer(minLength: 0)
                    recipientPortrait
                        .frame(width: 112, height: 140)
                        .offset(x: 10, y: 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.bottom, 52)
                .allowsHitTesting(false)

                // Soft fade so the pledge strip stays readable over the photo.
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                // Pledge CTA with stacked pledgers — tapping the card opens the
                // pool so people can see who committed.
                pledgeStrip
                    .padding(10)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ThemeRadius.lg, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .cardElevation()
        }
        .buttonStyle(.plain)
        .scrollTransition(.animated, axis: .horizontal) { content, phase in
            content
                .scaleEffect(phase.isIdentity ? 1 : 0.96)
                .opacity(phase.isIdentity ? 1 : 0.88)
        }
        .accessibilityLabel("\(item.headline), $\(Int(item.pool.targetAmount)) goal, \(item.pool.contributors.count) pledged")
    }

    private var recipientPortrait: some View {
        ZStack {
            if let url = item.portraitURL {
                CachedAsyncImage(url: url.absoluteString, width: 400)
            } else {
                Color.gradient(for: .coral)
                Text(String(item.recipient.prefix(1)).uppercased())
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 112, height: 140)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
    }

    private var pledgeStrip: some View {
        HStack(spacing: 8) {
            pledgersStack

            Text("Pledge")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            Text("$\(Int(item.pool.currentAmount))")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.coral)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var pledgersStack: some View {
        let pledgers = Array(item.pool.contributors.prefix(4))
        return HStack(spacing: -8) {
            ForEach(Array(pledgers.enumerated()), id: \.element.id) { index, person in
                AvatarView(name: person.name, grad: person.avatarGrad, size: 22)
                    .overlay(Circle().stroke(Color.coral, lineWidth: 1.5))
                    .zIndex(Double(pledgers.count - index))
            }
            if item.pool.contributors.count > 4 {
                Text("+\(item.pool.contributors.count - 4)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.ink.opacity(0.85))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.coral, lineWidth: 1.5))
            }
        }
    }
}
