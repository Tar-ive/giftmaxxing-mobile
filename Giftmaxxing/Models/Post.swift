import Foundation

struct Post: Identifiable, Codable, Hashable {
    let id: String
    var user: String
    var time: String
    var product: Product
    var caption: String
    var likes: Int
    var liked: Bool
    var saved: Bool
    var comments: [Comment]
    var commentCount: Int?
    var source: String?
    var url: String?
    var productUrl: String?
    var rec: Bool?
    var reason: String?

    var displayCommentCount: Int {
        commentCount ?? comments.count
    }

    enum CodingKeys: String, CodingKey {
        case id, user, time, product, caption, likes, liked, saved
        case comments, commentCount, source, url, productUrl, rec, reason
    }

    init(
        id: String,
        user: String,
        time: String,
        product: Product,
        caption: String,
        likes: Int,
        liked: Bool = false,
        saved: Bool = false,
        comments: [Comment] = [],
        commentCount: Int? = nil,
        source: String? = nil,
        url: String? = nil,
        productUrl: String? = nil,
        rec: Bool? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.user = user
        self.time = time
        self.product = product
        self.caption = caption
        self.likes = likes
        self.liked = liked
        self.saved = saved
        self.comments = comments
        self.commentCount = commentCount
        self.source = source
        self.url = url
        self.productUrl = productUrl
        self.rec = rec
        self.reason = reason
    }
}

struct Comment: Identifiable, Codable, Hashable {
    let id: String
    var user: String
    var text: String
}
