import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: Tab = .feed
    @Published var isAuthenticated = false
    @Published var currentUser: AppUser?
    @Published var cartItems: [CartItem] = []

    // Maxi is the app's core agent — reachable from anywhere via the floating
    // button (Amazon Rufus-style) and the home top bar.
    @Published var showMaxi = false

    // Set before jumping to the Search tab to land on a specific mode
    // (e.g. the camera button opens Visual search directly).
    @Published var pendingSearchTab: SearchTab?

    // Image captured via the share extension or the screenshots rail —
    // SearchTabsView picks it up and runs visual search immediately.
    @Published var pendingCaptureImage: UIImage?
    @Published var pendingCaptureNote: String?

    func openSearch(_ tab: SearchTab) {
        pendingSearchTab = tab
        selectedTab = .search
    }

    // Route a capture (shared image/URL or tapped screenshot) into visual search.
    func handleCapture(image: UIImage?, url: String? = nil) {
        if let image {
            pendingCaptureImage = image
            pendingCaptureNote = nil
        } else if let url {
            // Login-walled pages (Instagram/Pinterest) can't be fetched
            // server-side; steer the user to the screenshot path.
            pendingCaptureNote = "Links from \(URL(string: url)?.host ?? "that app") can't be read directly — screenshot the post and share that instead."
        }
        openSearch(.visual)
    }

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
