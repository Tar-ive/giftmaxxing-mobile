import Foundation

struct Pool: Identifiable, Codable {
    let id: String
    var title: String
    var forUser: String
    var occasion: String?
    var targetAmount: Double
    var currentAmount: Double
    var contributors: [PoolContributor]
    var createdAt: Date?
    var deadline: Date?
    var product: Product?
    // Image captured via the share extension (Instagram/Pinterest post) —
    // filename inside the app-group `pool-images/` folder.
    var localImageFile: String?
    // Where the inspiration came from (e.g. the shared Instagram URL).
    var sourceUrl: String?

    var progressPercent: Double {
        guard targetAmount > 0 else { return 0 }
        return min(currentAmount / targetAmount, 1.0)
    }
}

struct PoolContributor: Identifiable, Codable {
    let id: String
    var name: String
    var amount: Double
    var avatarGrad: GradientStyle
}
