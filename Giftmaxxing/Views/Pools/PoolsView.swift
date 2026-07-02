import SwiftUI

struct PoolsView: View {
    @State private var pools: [Pool] = Pool.samples
    @State private var showCreateSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Active pools
                    ForEach(pools) { pool in
                        PoolCard(pool: pool)
                    }

                    // Create new pool CTA
                    Button(action: { showCreateSheet = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.coral)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start a gift pool")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.ink)
                                Text("Split the cost of a gift with friends")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(Color.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .background(Color.surface)
            .navigationTitle("Gift Pools")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showCreateSheet) {
                CreatePoolSheet()
            }
        }
    }
}

struct PoolCard: View {
    let pool: Pool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pool.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.ink)
                    HStack(spacing: 4) {
                        Text("for")
                            .foregroundStyle(.secondary)
                        Text(pool.forUser)
                            .foregroundStyle(Color.coral)
                            .fontWeight(.medium)
                        if let occasion = pool.occasion {
                            Text("· \(occasion)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }

                Spacer()

                if let product = pool.product {
                    GradientCard(
                        grad: product.grad,
                        emoji: product.emoji,
                        imageURL: product.image,
                        size: 48
                    )
                }
            }

            // Progress bar
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.cream)
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [Color.coral, Color(hex: "#FF9A76")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * pool.progressPercent, height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("$\(Int(pool.currentAmount)) raised")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.coral)
                    Spacer()
                    Text("$\(Int(pool.targetAmount)) goal")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            // Contributors
            HStack(spacing: -8) {
                ForEach(pool.contributors.prefix(5)) { contributor in
                    AvatarView(name: contributor.name, grad: contributor.avatarGrad, size: 28)
                        .overlay(Circle().stroke(Color.surface, lineWidth: 2))
                }

                if pool.contributors.count > 5 {
                    Text("+\(pool.contributors.count - 5)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.ink.opacity(0.5))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.surface, lineWidth: 2))
                }

                Spacer()

                Button(action: {}) {
                    Text("Contribute")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.coral)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(16)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

struct CreatePoolSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var forUser = ""
    @State private var targetAmount = ""
    @State private var occasion = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Pool details") {
                    TextField("Gift name", text: $title)
                    TextField("For whom?", text: $forUser)
                    TextField("Occasion", text: $occasion)
                    TextField("Target amount ($)", text: $targetAmount)
                        .keyboardType(.decimalPad)
                }

                Section {
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Create Pool")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.coral)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("New Gift Pool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

extension Pool {
    static let samples: [Pool] = [
        Pool(
            id: "pool1",
            title: "Mini Instant Camera",
            forUser: "Maya",
            occasion: "Birthday",
            targetAmount: 89,
            currentAmount: 52,
            contributors: [
                PoolContributor(id: "c1", name: "Jules", amount: 22, avatarGrad: .lilac),
                PoolContributor(id: "c2", name: "Noor", amount: 30, avatarGrad: .butter),
            ],
            product: Product(id: "camera", name: "Mini Instant Camera", brand: "Halo", price: 89, grad: .sky, emoji: "📷")
        ),
        Pool(
            id: "pool2",
            title: "Wireless Buds Pro",
            forUser: "Sam",
            occasion: "Farewell",
            targetAmount: 149,
            currentAmount: 75,
            contributors: [
                PoolContributor(id: "c3", name: "Maya", amount: 25, avatarGrad: .rose),
                PoolContributor(id: "c4", name: "Theo", amount: 25, avatarGrad: .sage),
                PoolContributor(id: "c5", name: "Jules", amount: 25, avatarGrad: .lilac),
            ],
            product: Product(id: "buds", name: "Wireless Buds Pro", brand: "Aera", price: 149, grad: .lilac, emoji: "🎧")
        ),
    ]
}
