import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: Tab = .feed
    @Published var isAuthenticated = false
    @Published var currentUser: AppUser?
    @Published var cartItems: [CartItem] = []

    var cartCount: Int { cartItems.count }

    func addToCart(_ item: CartItem) {
        cartItems.append(item)
    }

    func removeFromCart(at index: Int) {
        guard cartItems.indices.contains(index) else { return }
        cartItems.remove(at: index)
    }
}

struct CartItem: Identifiable {
    let id: String
    let product: Product
    let quantity: Int
}

struct AppUser: Identifiable, Codable {
    let id: String
    var name: String
    var handle: String
    var email: String?
    var imageUrl: String?
    var grad: String
}

enum Tab: String, CaseIterable {
    case feed = "Home"
    case search = "Search"
    case swipe = "Swipe"
    case events = "Events"
    case more = "More"

    var icon: String {
        switch self {
        case .feed: return "house.fill"
        case .search: return "magnifyingglass"
        case .swipe: return "rectangle.portrait.on.rectangle.portrait.angled.fill"
        case .events: return "calendar"
        case .more: return "ellipsis.circle"
        }
    }
}
