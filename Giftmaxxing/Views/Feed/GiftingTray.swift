import SwiftUI

// Stories-style gifting tray on Home. Every group gift in flight and active
// pool rides here as a tappable bubble (they used to hide on the Circles
// tab), plus start bubbles so both plays can begin right from Home.
struct GiftingTray: View {
    @ObservedObject private var groupGifts = GroupGiftStore.shared
    @ObservedObject private var pools = PoolsStore.shared
    @State private var showPools = false
    @State private var viewingPool: Pool?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                // In-flight group gifts — coral ring = your swipe is missing.
                ForEach(groupGifts.gifts) { gift in
                    NavigationLink(destination: GroupGiftDetailView(giftId: gift.id)) {
                        TrayBubble(
                            label: "For \(gift.recipient)",
                            ring: gift.youSwiped || gift.poolId != nil ? Color.ink.opacity(0.15) : Color.coral
                        ) {
                            AvatarView(name: gift.recipient, grad: .lilac, size: 52)
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }

                // Active pools — the ring is the funding progress.
                ForEach(pools.pools) { pool in
                    Button {
                        viewingPool = pool
                    } label: {
                        TrayBubble(label: "For \(pool.forUser)", ring: .clear) {
                            ZStack {
                                Circle()
                                    .stroke(Color.cream, lineWidth: 3)
                                Circle()
                                    .trim(from: 0, to: max(0.03, min(1, pool.progressPercent)))
                                    .stroke(Color.coral, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                Image(systemName: "banknote.fill").foregroundStyle(Color.coral)
                                    .font(.system(size: 22))
                            }
                            .frame(width: 52, height: 52)
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }

                // Start bubbles — group gifts and pools begin right on Home.
                NavigationLink(destination: GroupGiftCreateView()) {
                    TrayBubble(label: "Group gift", ring: .clear) {
                        startCircle(icon: "person.3.fill")
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                Button {
                    showPools = true
                } label: {
                    TrayBubble(label: "Gift pool", ring: .clear) {
                        startCircle(icon: "banknote.fill")
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showPools) { PoolsView() }
        .sheet(item: $viewingPool) { pool in
            PoolDetailView(poolId: pool.id)
        }
    }

    private func startCircle(icon: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.coralSoft)
            Circle()
                .stroke(Color.coral.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.coral)
        }
        .frame(width: 52, height: 52)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.coral, .white)
        }
    }
}

private struct TrayBubble<Content: View>: View {
    let label: String
    let ring: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 5) {
            content
                .overlay(
                    Circle().stroke(ring, lineWidth: 2.5).padding(-4)
                )
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .frame(maxWidth: 64)
        }
        .contentShape(Rectangle())
    }
}
