import Foundation

public struct Pool: Identifiable, Codable {
    public let id: String
    public var title: String
    public var forUser: String
    public var occasion: String?
    public var targetAmount: Double
    public var currentAmount: Double
    public var contributors: [PoolContributor]
    public var createdAt: Date?
    public var deadline: Date?
    public var product: Product?
    // Image captured via the share extension (Instagram/Pinterest post) —
    // filename inside the app-group `pool-images/` folder.
    public var localImageFile: String?
    // Where the inspiration came from (e.g. the shared Instagram URL).
    public var sourceUrl: String?

    public init(
        id: String,
        title: String,
        forUser: String,
        occasion: String? = nil,
        targetAmount: Double,
        currentAmount: Double,
        contributors: [PoolContributor],
        createdAt: Date? = nil,
        deadline: Date? = nil,
        product: Product? = nil,
        localImageFile: String? = nil,
        sourceUrl: String? = nil
    ) {
        self.id = id
        self.title = title
        self.forUser = forUser
        self.occasion = occasion
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.contributors = contributors
        self.createdAt = createdAt
        self.deadline = deadline
        self.product = product
        self.localImageFile = localImageFile
        self.sourceUrl = sourceUrl
    }


    public var progressPercent: Double {
        guard targetAmount > 0 else { return 0 }
        return min(currentAmount / targetAmount, 1.0)
    }
}

public struct PoolContributor: Identifiable, Codable {
    public let id: String
    public var name: String
    public var amount: Double
    public var avatarGrad: GradientStyle

    public init(
        id: String,
        name: String,
        amount: Double,
        avatarGrad: GradientStyle
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.avatarGrad = avatarGrad
    }

}
