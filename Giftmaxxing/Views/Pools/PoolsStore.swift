import Foundation

// Local-first pools store — iOS port of web/lib/pools.ts behavior. Pools are
// persisted on-device (web keeps them server-side per signed-in user; until
// auth lands on iOS the store keeps the same UX working offline). Server sync
// via POST /pools + /pools/{id}/contribute attaches once sign-in ships (#5).
@MainActor
final class PoolsStore: ObservableObject {
    @Published private(set) var pools: [Pool] = []

    private static let storageKey = "giftmaxxing_pools_local"

    init() {
        load()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([Pool].self, from: data),
           !saved.isEmpty {
            pools = saved
        } else {
            pools = Pool.samples
        }
    }

    @discardableResult
    func create(title: String, forUser: String, occasion: String, targetAmount: Double) -> Pool {
        let pool = Pool(
            id: "pool_\(Int(Date().timeIntervalSince1970 * 1000))",
            title: title,
            forUser: forUser.isEmpty ? "a friend" : forUser,
            occasion: occasion.isEmpty ? nil : occasion,
            targetAmount: targetAmount,
            currentAmount: 0,
            contributors: [],
            createdAt: Date(),
            product: nil
        )
        pools.insert(pool, at: 0)
        persist()
        AnalyticsEngine.shared.trackScreenView(screen: "pool_created")
        return pool
    }

    // Mirrors web contributeToPool: bump raised total + record the contributor.
    func contribute(_ amount: Double, to poolId: String) {
        guard amount > 0,
              let idx = pools.firstIndex(where: { $0.id == poolId }) else { return }
        var pool = pools[idx]
        pool.currentAmount += amount
        if let existing = pool.contributors.firstIndex(where: { $0.name == "You" }) {
            pool.contributors[existing].amount += amount
        } else {
            pool.contributors.append(
                PoolContributor(id: "you_\(poolId)", name: "You", amount: amount, avatarGrad: .coral)
            )
        }
        pools[idx] = pool
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pools) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
