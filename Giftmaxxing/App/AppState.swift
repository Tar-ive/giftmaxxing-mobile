import SwiftUI
import GiftmaxxingCore

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: Tab = .feed
    @Published var isAuthenticated = false
    @Published var currentUser: AppUser?
    // The cart lives in CartStore (per-person sections, synced through /me) —
    // AppState's old flat `cartItems` stub was never read by any view.


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
    // of its own. ContentView renders MaxiFloatingButton and presents MaxiView
    // as a sheet when this is set. The Home search bar's mic sets it too.
    @Published var showMaxi = false
    // Opening Maxi already focused on someone: the Cart's per-person "Ask Maxi"
    // and a Gift Board both seed the brief so the conversation starts mid-job
    // instead of at "who is this for?".
    @Published var maxiSeedRecipient: String?
    // Focused flows (DMs, challenges, taste interview) suppress the global
    // floating button. Use a depth counter so nested sheets restore it safely.
    @Published private(set) var maxiFABSuppressionDepth = 0

    // Tabs where a concierge makes sense: browsing (Home), the people you shop
    // for (Circles), and your own gifting life (You). Swipe and Post are
    // hands-on, full-bleed surfaces — a swipe deck and a camera — where a
    // floating button is in the way of the actual interaction, not a shortcut.
    //
    // Home IS included. It briefly wasn't, because the FAB sits in the same
    // corner as each feed card's Pool / Gift-board buttons — but those SCROLL,
    // so no fixed inset can ever clear them. Moving Maxi into the header was
    // the wrong fix: it demoted the concierge to a toolbar icon. The right one
    // is `isScrolling`, below.
    private static let maxiFABTabs: Set<Tab> = [.feed, .circles, .you]

    // The feed is scrolling right now. The FAB fades down (never unmounts) while
    // it is, which is what lets it share a corner with the cards' own controls:
    // you never reach for a button mid-scroll, and by the time you stop it is
    // back at full strength.
    @Published var isScrolling = false

    /// Faded and non-interactive, but still on screen — no layout change, so
    /// nothing can jitter.
    var maxiFABDimmed: Bool { isScrolling && selectedTab == .feed }

    // MOUNTING is deliberately independent of scrolling. Gating the `if` on
    // isScrolling made SwiftUI insert and remove the button on every scroll
    // start/stop — a transition churn that read as the FAB jittering around the
    // corner. It stays mounted; only its opacity moves (see fabDimmed).
    var showsMaxiFAB: Bool {
        Self.maxiFABTabs.contains(selectedTab)
            && maxiFABSuppressionDepth == 0
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

    // The DM inbox lives in Circles (your people), not on Home. Push taps and
    // any other "open messages" intent route through here.
    @Published var pendingMessages = false
    // The activity bell lives in Circles now, so a notification push switches
    // tabs rather than pushing an inbox onto the Home stack.
    @Published var pendingActivity = false

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

    func openMessages() {
        selectedTab = .circles
        pendingMessages = true
    }

    func openActivity() {
        selectedTab = .circles
        pendingActivity = true
    }

    func openBoard(_ boardId: String) {
        selectedTab = .you
        pendingBoardId = boardId
    }

    func openBoardsHome() {
        selectedTab = .you
        pendingBoardsHome = true
    }

    /// Search is a TAB now, not a modal. Switch to it and hand it the mode —
    /// `showSearch` still exists only because a couple of legacy call sites
    /// present it as a sheet; new code should route through here.
    func openSearch(_ tab: SearchTab) {
        pendingSearchTab = tab
        selectedTab = .search
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
//               return from background, and sign-in all reset here)
//   Swipe     — taste training + Gift Boards (feeds personalization)
//   Search    — gifts, brands, and visual search (people once invited)
//   Circles   — INVITE-ONLY (InviteAccess): your people + their dates,
//               collaborative boards, pools, swipe challenges. Absent from the
//               tab bar until a code is redeemed, so nobody lands in an empty
//               room.
//   You       — the public gifting profile + settings (Shop and Intentional
//               Discover live here as rows, not tabs)
// Posting (UGC) is gone: creating content was a social-network job, not a
// gift-finding one. Maxi (the AI concierge) is NOT a tab — it's the floating
// button over every tab (MaxiFloatingButton, rendered by ContentView). The
// Gift Journey (GiftJourneyEngine) nudges and the Home search bar's mic open
// the same conversation.
enum Tab: String, CaseIterable {
    case feed = "Home"
    case swipe = "Swipe"
    case search = "Search"
    case circles = "Circles"
    case you = "You"

    // What the tab bar actually renders. Circles only exists for invitees;
    // anything measuring tab slots (CoachMarks) must use this, not allCases.
    static func visible(inviteUnlocked: Bool) -> [Tab] {
        inviteUnlocked ? [.feed, .swipe, .search, .circles, .you] : [.feed, .swipe, .search, .you]
    }

    // One stroke system across the bar: outline at rest, filled when selected.
    // Everything was previously filled at every state, which flattened the
    // selected/unselected distinction into a colour change alone and mixed
    // weights (a hand-tuned angled-rectangle glyph next to stock symbols).
    // These are the stock SF Symbol pairs, so weights and optical sizes match.
    var icon: String { icon(selected: false) }

    func icon(selected: Bool) -> String {
        switch self {
        case .feed: return selected ? "house.fill" : "house"
        case .swipe: return selected ? "rectangle.stack.fill" : "rectangle.stack"
        // Search took the centre slot from Post. Posting is gone entirely now;
        // searching for a gift is the thing people open the app to do.
        case .search: return selected ? "magnifyingglass.circle.fill" : "magnifyingglass"
        case .circles: return selected ? "person.2.fill" : "person.2"
        case .you: return selected ? "person.crop.circle.fill" : "person.crop.circle"
        }
    }
}
