import UIKit

// Local-first pools store — iOS port of web/lib/pools.ts behavior. Pools are
// persisted on-device (web keeps them server-side per signed-in user; until
// auth lands on iOS the store keeps the same UX working offline). Server sync
// via POST /pools + /pools/{id}/contribute attaches once sign-in ships (#5).
@MainActor
final class PoolsStore: ObservableObject {
    // Single source of truth — the Home rail, the Pools screen and the
    // share-capture flow all observe the same instance.
    static let shared = PoolsStore()

    @Published private(set) var pools: [Pool] = []

    private static let storageKey = "giftmaxxing_pools_local"

    // Captured pool images live in the app group so they survive reinstalls
    // of either the app or the extension.
    static var imagesDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: CaptureInbox.appGroupID)?
            .appendingPathComponent("pool-images", isDirectory: true)
    }

    static func image(named file: String?) -> UIImage? {
        guard let file, let dir = imagesDirectory else { return nil }
        return UIImage(contentsOfFile: dir.appendingPathComponent(file).path)
    }

    // Persist a captured image; returns the filename to store on the Pool.
    static func saveCaptureImage(_ image: UIImage) -> String? {
        guard let dir = imagesDirectory,
              let jpeg = image.jpegData(compressionQuality: 0.85) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "capture-\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        do {
            try jpeg.write(to: dir.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

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
    func create(
        title: String,
        forUser: String,
        occasion: String,
        targetAmount: Double,
        product: Product? = nil,
        localImageFile: String? = nil,
        sourceUrl: String? = nil
    ) -> Pool {
        let pool = Pool(
            id: "pool_\(Int(Date().timeIntervalSince1970 * 1000))",
            title: title,
            forUser: forUser.isEmpty ? "a friend" : forUser,
            occasion: occasion.isEmpty ? nil : occasion,
            targetAmount: targetAmount,
            currentAmount: 0,
            contributors: [],
            createdAt: Date(),
            product: product,
            localImageFile: localImageFile,
            sourceUrl: sourceUrl
        )
        pools.insert(pool, at: 0)
        persist()
        AnalyticsEngine.shared.trackScreenView(screen: "pool_created")
        return pool
    }

    // Group-gift pledge round: record a named pledge ("Sarah — $25") so the
    // leaderboard reflects the whole friend group, not just this device.
    // Payments/delivery are out of scope for now — this is the coordination
    // layer the group settles up around.
    func pledge(name: String, amount: Double, to poolId: String) {
        guard amount > 0,
              let idx = pools.firstIndex(where: { $0.id == poolId }) else { return }
        var pool = pools[idx]
        pool.currentAmount += amount
        if let existing = pool.contributors.firstIndex(where: { $0.name == name }) {
            pool.contributors[existing].amount += amount
        } else {
            let grads: [GradientStyle] = [.peach, .rose, .butter, .lilac, .sky, .sage, .coral]
            pool.contributors.append(
                PoolContributor(
                    id: "pledge_\(Int(Date().timeIntervalSince1970 * 1000))",
                    name: name,
                    amount: amount,
                    avatarGrad: name == "You" ? .coral : grads[abs(name.hashValue) % grads.count]
                )
            )
        }
        pools[idx] = pool
        persist()
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
