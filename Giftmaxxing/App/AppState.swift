import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: Tab = .feed
    @Published var isAuthenticated = false
    @Published var currentUser: AppUser?
    @Published var cartItems: [CartItem] = []


    // Search is a modal layer over any tab (HIG: search is a mode, not a
    // destination — it kept a tab slot from features that matter more).
    // Set pendingSearchTab before presenting to land on a specific mode
    // (e.g. the camera button opens Visual search directly).
    @Published var showSearch = false
    @Published var pendingSearchTab: SearchTab?

    // Image captured via the share extension or the screenshots rail —
    // SearchTabsView picks it up and runs visual search immediately.
    @Published var pendingCaptureImage: UIImage?
    @Published var pendingCaptureNote: String?

    // Pool-intent capture ("Start a gift pool" in the share extension) —
    // ContentView presents the create-pool sheet prefilled with these.
    @Published var poolCaptureImage: UIImage?
    @Published var poolCaptureURL: String?
    @Published var showCreatePoolFromCapture = false

    // Circle deep link (giftmaxxing://circle/<id> or a pasted /circle/<id>
    // web URL) — CirclesView picks this up and pushes the circle page, where
    // the inline join card handles new arrivals (web parity).
    @Published var pendingCircleId: String?

    // Birthday-freebies notification tap — ContentView presents the perks
    // sheet at root (works from any tab).
    @Published var showBirthdayPerks = false

    // Maxi (the AI concierge) is a floating button over every tab — not a tab
    // of its own. ContentView presents MaxiView as a sheet when this is set.
    @Published var showMaxi = false

    func openCircle(_ circleId: String) {
        selectedTab = .circles
        pendingCircleId = circleId
    }

    func openSearch(_ tab: SearchTab) {
        pendingSearchTab = tab
        showSearch = true
    }

    // Route a capture (shared image/URL or tapped screenshot) by intent.
    func handleCapture(image: UIImage?, url: String? = nil, intent: CaptureInbox.Intent = .search) {
        switch intent {
        case .pool:
            poolCaptureImage = image
            poolCaptureURL = url
            selectedTab = .feed
            showCreatePoolFromCapture = true

        case .search:
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

// The tab bar IS the product statement (HIG: 3–5 tabs, every core journey
// visible — nothing important behind a "More" screen):
//   Home      — the personalized feed
//   Swipe     — taste training (feeds personalization)
//   Shop      — the curated shop feed: real products + birthday freebies
//   Circles   — your people + their dates: circles, events & reminders,
//               group gifts, pools, swipe challenges
//   You       — profile, orders, settings
// Maxi (the AI concierge) is NOT a tab — it's a floating button over every
// tab (MaxiFloatingButton in ContentView, driven by AppState.showMaxi).
enum Tab: String, CaseIterable {
    case feed = "Home"
    case swipe = "Swipe"
    case shop = "Shop"
    case circles = "Circles"
    case you = "You"

    var icon: String {
        switch self {
        case .feed: return "house.fill"
        case .swipe: return "rectangle.portrait.on.rectangle.portrait.angled.fill"
        case .shop: return "bag.fill"
        case .circles: return "person.2.fill"
        case .you: return "person.crop.circle"
        }
    }
}
