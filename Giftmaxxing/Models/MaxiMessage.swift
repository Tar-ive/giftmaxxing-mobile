import Foundation

struct MaxiMessage: Identifiable {
    let id: String
    var role: MessageRole
    var text: String
    var products: [MaxiProduct]
    var steps: [MaxiStep]
    var chips: [String]
    var timestamp: Date

    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        text: String,
        products: [MaxiProduct] = [],
        steps: [MaxiStep] = [],
        chips: [String] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.products = products
        self.steps = steps
        self.chips = chips
        self.timestamp = timestamp
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
}

struct MaxiProduct: Identifiable, Codable {
    let postId: String
    var title: String
    var price: Double?
    var brand: String?
    var image: String?
    var category: String?

    var id: String { postId }
}

struct MaxiStep: Identifiable, Codable {
    var tool: String
    var label: String
    var detail: String?

    var id: String { "\(tool)-\(label)" }
}

struct MaxiAgentReply: Codable {
    var say: String
    var pins: [MaxiProduct]
    var actions: [MaxiAction]
    var steps: [MaxiStep]
    var source: String

    struct MaxiAction: Codable {
        var type: String
        var postIds: [String]?
    }
}
