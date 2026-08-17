import SwiftUI
import GiftmaxxingCore

// Pool detail — the "look before you chip in" screen. Shows the gift, the
// goal, and crucially WHO already committed and how much: the visible list is
// the social pressure that makes pools fund.
struct PoolDetailView: View {
    let poolId: String

    @ObservedObject private var store = PoolsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showContribute = false
    @State private var showSource = false

    // Live pool from the store so contributions reflect immediately.
    private var pool: Pool? {
        store.pools.first(where: { $0.id == poolId })
    }

    var body: some View {
        NavigationStack {
            if let pool {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(pool)
                        progress(pool)
                        contributors(pool)

                        if let source = pool.sourceUrl, URL(string: source) != nil {
                            Button {
                                showSource = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "link")
                                        .font(.system(size: 12))
                                    Text("See the original post")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(Color.coral)
                            }
                        }
                    }
                    .padding(18)
                }
                .background(Color.surface)
                .navigationTitle("Gift pool")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                            .foregroundStyle(.secondary)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    bottomBar(pool)
                }
                .sheet(isPresented: $showContribute) {
                    ContributeSheet(pool: pool) { amount in
                        store.contribute(amount, to: pool.id)
                    }
                    .presentationDetents([.medium])
                }
                .sheet(isPresented: $showSource) {
                    if let source = pool.sourceUrl, let url = URL(string: source) {
                        SafariView(url: url)
                    }
                }
            }
        }
        .onAppear {
            AnalyticsEngine.shared.trackScreenView(screen: "pool_detail")
        }
    }

    private func header(_ pool: Pool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // The gift itself — captured post image, product image, or emoji.
            ZStack {
                if let local = PoolsStore.image(named: pool.localImageFile) {
                    Image(uiImage: local)
                        .resizable()
                        .scaledToFill()
                } else if let product = pool.product {
                    ZStack {
                        Color.gradient(for: product.grad)
                        Text(product.emoji).font(.system(size: 56))
                        if let image = product.image {
                            CachedAsyncImage(url: image, width: 700)
                        }
                    }
                } else {
                    ZStack {
                        Color.coralSoft
                        BrandGlyph(size: 34, tile: false).font(.system(size: 56))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 4) {
                Text(pool.title)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.ink)

                HStack(spacing: 4) {
                    Text("for")
                        .foregroundStyle(.secondary)
                    Text(pool.forUser)
                        .foregroundStyle(Color.coral)
                        .fontWeight(.semibold)
                    if let occasion = pool.occasion {
                        Text("· \(occasion)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 14))
            }
        }
    }

    private func progress(_ pool: Pool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.cream).frame(height: 10)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.coral, Color(hex: "#FF9A76")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * pool.progressPercent, height: 10)
                }
            }
            .frame(height: 10)

            HStack {
                Text("$\(Int(pool.currentAmount)) raised")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.coral)
                Spacer()
                if pool.progressPercent >= 1 {
                    Label("Funded", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("$\(Int(max(pool.targetAmount - pool.currentAmount, 0))) to go · $\(Int(pool.targetAmount)) goal")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func contributors(_ pool: Pool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pool.contributors.isEmpty
                 ? "No one's in yet"
                 : "\(pool.contributors.count) in so far")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.ink)

            if pool.contributors.isEmpty {
                Text("Be the first to chip in — everyone else sees your name here.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(pool.contributors.sorted(by: { $0.amount > $1.amount })) { person in
                        HStack(spacing: 10) {
                            AvatarView(name: person.name, grad: person.avatarGrad, size: 34)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(person.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.ink)
                                Text("committed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("$\(Int(person.amount))")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.coral)
                        }
                        .padding(.vertical, 8)

                        if person.id != pool.contributors.sorted(by: { $0.amount > $1.amount }).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func bottomBar(_ pool: Pool) -> some View {
        HStack(spacing: 10) {
            ShareLink(
                item: "Chip in for \(pool.title) for \(pool.forUser)! $\(Int(pool.currentAmount)) of $\(Int(pool.targetAmount)) raised on Giftmaxxing 🎁",
                subject: Text("Gift pool: \(pool.title)")
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                    Text("Invite")
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.coral)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.coralSoft)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Button {
                showContribute = true
            } label: {
                Text(pool.progressPercent >= 1 ? "Add more 🎉" : "Chip in")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
