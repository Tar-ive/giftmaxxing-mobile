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

    // A challenge invite opened IN the app (deep link or tapped DM invite) —
    // ContentView presents the native swipe deck instead of bouncing to web.
    @Published var pendingChallengeId: String?

    // Maxi (the AI concierge) is a floating button over every tab — not a tab
    // of its own. ContentView presents MaxiView as a sheet when this is set.
    @Published var showMaxi = false
    // Focused flows (DMs, challenges, taste interview) suppress the global
    // floating button. Use a depth counter so nested sheets restore it safely.
    @Published private(set) var maxiFABSuppressionDepth = 0

    var showsMaxiFAB: Bool {
        maxiFABSuppressionDepth == 0
            && !showMaxi
            && !showSearch
            && !showCreatePoolFromCapture
    }

    func suppressMaxiFAB() {
        maxiFABSuppressionDepth += 1
    }

    func unsuppressMaxiFAB() {
        maxiFABSuppressionDepth = max(0, maxiFABSuppressionDepth - 1)
    }

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
//   Home      — the personalized feed (always the landing tab: cold launch,
//               return from background, and sign-in all reset here)
//   Swipe     — taste training + Gift Boards (feeds personalization)
//   Post      — photo/video gift finds, safety-screened before publication
//   Circles   — your people + their dates: circles, events & reminders,
//               collaborative boards, pools, swipe challenges
//   You       — the public gifting profile + settings (Shop and Intentional
//               Discover live here as rows, not tabs)
// Maxi (the AI concierge) is NOT a tab and no longer a floating button — its
// nudges arrive through the Gift Journey (GiftJourneyEngine) and the Home
// search bar's mic still opens the full conversation.
enum Tab: String, CaseIterable {
    case feed = "Home"
    case swipe = "Swipe"
    case create = "Post"
    case circles = "Circles"
    case you = "You"

    var icon: String {
        switch self {
        case .feed: return "house.fill"
        case .swipe: return "rectangle.portrait.on.rectangle.portrait.angled.fill"
        case .create: return "plus.circle.fill"
        case .circles: return "person.2.fill"
        case .you: return "person.crop.circle"
        }
    }
}
