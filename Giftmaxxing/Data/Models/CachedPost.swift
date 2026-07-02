import Foundation
import SwiftData

@Model
final class CachedPost {
    @Attribute(.unique) var postId: String
    var user: String
    var time: String
    var caption: String
    var likes: Int
    var liked: Bool
    var saved: Bool
    var commentCount: Int
    var source: String?
    var url: String?
    var productUrl: String?
    var rec: Bool
    var reason: String?

    var productId: String
    var productName: String
    var productBrand: String
    var productPrice: Double
    var productWas: Double?
    var productGrad: String
    var productEmoji: String
    var productImage: String?

    var cachedAt: Date
    var feedPosition: Int

    init(from post: Post, position: Int = 0) {
        self.postId = post.id
        self.user = post.user
        self.time = post.time
        self.caption = post.caption
        self.likes = post.likes
        self.liked = post.liked
        self.saved = post.saved
        self.commentCount = post.displayCommentCount
        self.source = post.source
        self.url = post.url
        self.productUrl = post.productUrl
        self.rec = post.rec ?? false
        self.reason = post.reason
        self.productId = post.product.id
        self.productName = post.product.name
        self.productBrand = post.product.brand
        self.productPrice = post.product.price
        self.productWas = post.product.was
        self.productGrad = post.product.grad.rawValue
        self.productEmoji = post.product.emoji
        self.productImage = post.product.image
        self.cachedAt = Date()
        self.feedPosition = position
    }

    func toPost() -> Post {
        let product = Product(
            id: productId,
            name: productName,
            brand: productBrand,
            price: productPrice,
            was: productWas,
            grad: GradientStyle(rawValue: productGrad) ?? .peach,
            emoji: productEmoji,
            image: productImage
        )
        return Post(
            id: postId,
            user: user,
            time: time,
            product: product,
            caption: caption,
            likes: likes,
            liked: liked,
            saved: saved,
            comments: [],
            commentCount: commentCount,
            source: source,
            url: url,
            productUrl: productUrl,
            rec: rec,
            reason: reason
        )
    }
}
