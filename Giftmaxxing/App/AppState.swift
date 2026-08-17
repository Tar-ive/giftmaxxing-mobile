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

    // Circles (and the rest of the social layer) is invite-only — a locked
    // user who taps a circle link or the You-tab row gets the code sheet.
    @Published var showInviteCode = false

    // Birthday-freebies notification tap — ContentView presents the perks
    // sheet at root (works from any tab).
    @Published var showBirthdayPerks = false

    // Gift Board deep link (post-save toast "View") — MoreView consumes these:
    // selects the You page's Gift Boards tab and, for pendingBoardId, pushes
    // the board detail.
    @Published var pendingBoardId: String?
    @Published var pendingBoardsHome = false

    // Birthday-journey notification taps: prefill presents ChallengeView with
    // the recipient set and the challenge auto-created; results opens the
    // responses (challenge_completed pushes route here too).
    struct ChallengePrefill: Identifiable {
        let id = UUID()
        let recipientName: String
    }
    @Published var pendingChallengePrefill: ChallengePrefill?
    @Published var showChallengeResults = false

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
        guard InviteAccess.shared.isUnlocked else {
            // Locked: the link is real, the door isn't open yet — ask for the
            // invite code instead of dropping the user on a missing tab.
            pendingCircleId = circleId
            showInviteCode = true
            return
        }
        selectedTab = .circles
        pendingCircleId = circleId
    }

    func openBoard(_ boardId: String) {
        selectedTab = .you
        pendingBoardId = boardId
    }

    func openBoardsHome() {
        selectedTab = .you
        pendingBoardsHome = true
    }

    func openSearch(_ tab: SearchTab) {
        pendingSearchTab = tab
        showSearch = true
    }

    // Route a capture (shared image/URL or tapped screenshot) by intent.
    func handleCapture(image: UIImage?, url: String? = nil, intent: CaptureInbox.Intent = .search) {
        switch intent {
        case .pool where InviteAccess.shared.isUnlocked:
            poolCaptureImage = image
            poolCaptureURL = url
            selectedTab = .feed
            showCreatePoolFromCapture = true

        // Gift pools are part of the invite-only social layer — a locked user
        // sharing into the app still gets the thing they came for: search.
        case .pool, .search:
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

// The tab bar IS the product statement — and the statement is "a useful gift
// SEARCH tool", not a social network:
//   Home      — the personalized feed (always the landing tab: cold launch,
//               return from background, and sign-in all reset here), with
//               Search and Maxi one tap away in its header
//   Swipe     — taste training, the engine behind every recommendation
//   Circles   — INVITE-ONLY (InviteAccess): your people + their dates,
//               pools, group gifts, swipe challenges. Absent from the tab bar
//               until a code is redeemed, so nobody lands in an empty room.
//   You       — the gifting profile, Gift Boards, Shop, settings
// Posting (UGC) is gone: creating content was a social-network job, not a
// gift-finding one. Maxi (the AI concierge) is not a tab — the Home search
// bar's mic opens the full conversation.
enum Tab: String, CaseIterable {
    case feed = "Home"
    case swipe = "Swipe"
    case circles = "Circles"
    case you = "You"

    // What the tab bar actually renders. Circles only exists for invitees;
    // anything measuring tab slots (CoachMarks) must use this, not allCases.
    static func visible(inviteUnlocked: Bool) -> [Tab] {
        inviteUnlocked ? [.feed, .swipe, .circles, .you] : [.feed, .swipe, .you]
    }

    var icon: String {
        switch self {
        case .feed: return "house.fill"
        case .swipe: return "rectangle.portrait.on.rectangle.portrait.angled.fill"
        case .circles: return "person.2.fill"
        case .you: return "person.crop.circle"
        }
    }
}
