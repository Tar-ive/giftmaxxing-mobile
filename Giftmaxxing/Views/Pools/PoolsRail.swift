import SwiftUI

// Home rail for active gift pools — replaces the Instagram-style stories tray.
// Giftmaxxing isn't a stories app: the social object is the POOL (a gift being
// funded together), so that's what lives at the top of Home.
struct PoolsRail: View {
    @ObservedObject private var store = PoolsStore.shared
    @State private var showPools = false
    @State private var viewingPool: Pool?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.coral)
                Text("Gift pools")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.ink)
                Spacer()
                Button("See all") {
                    showPools = true
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.coral)
            }
            .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.pools.prefix(8)) { pool in
                        Button {
                            viewingPool = pool
                        } label: {
                            PoolRailCard(pool: pool)
                        }
                        .buttonStyle(.plain)
                    }

                    // Start-a-pool tile — the same loop the share extension
                    // begins, reachable from Home too.
                    Button {
                        showPools = true
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(Color.coral)
                            Text("Start a pool")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.ink)
                        }
                        .frame(width: 132, height: 120)
                        .background(Color.coralSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
            }
        }
        .sheet(isPresented: $showPools) {
            PoolsView()
        }
        .sheet(item: $viewingPool) { pool in
            // Detail first — see who's in before you chip in.
            PoolDetailView(poolId: pool.id)
        }
    }
}

private struct PoolRailCard: View {
    let pool: Pool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Captured image (share extension), product image, or emoji fallback.
            ZStack {
                if let local = PoolsStore.image(named: pool.localImageFile) {
                    Image(uiImage: local)
                        .resizable()
                        .scaledToFill()
                } else if let product = pool.product {
                    ZStack {
                        Color.gradient(for: product.grad)
                        Text(product.emoji).font(.system(size: 26))
                        if let image = product.image {
                            CachedAsyncImage(url: image, width: 300)
                        }
                    }
                } else {
                    ZStack {
                        Color.coralSoft
                        Text("🎁").font(.system(size: 26))
                    }
                }
            }
            .frame(width: 132, height: 68)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(pool.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)

                // Funding progress — the number that makes pools feel alive.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.cream).frame(height: 5)
                        Capsule()
                            .fill(Color.coral)
                            .frame(width: geo.size.width * pool.progressPercent, height: 5)
                    }
                }
                .frame(height: 5)

                Text("$\(Int(pool.currentAmount)) of $\(Int(pool.targetAmount))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .frame(width: 132, height: 120)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
