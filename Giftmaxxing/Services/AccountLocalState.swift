import Foundation
import GiftmaxxingRecommendation

// Privacy boundary for the local-first gifting stores. Pools, group gifts,
// Gift Boards, Thoughtfulness Points, and the persona texts all live in
// UserDefaults — which is DEVICE-scoped, not account-scoped. Without this
// sweep, signing out and signing in as someone else on the same phone showed
// the previous person's private pools/boards to the new account.
//
// Rules:
//   • sign-out (userId → nil): clear everything private immediately.
//   • sign-in as a DIFFERENT account than the last one: clear before use.
//   • guest → first sign-in: KEEP — that guest data belongs to the human who
//     just claimed it (mirrors the server's anon-claim flow).
enum AccountLocalState {
    private static let lastIdentityKey = "giftmaxxing_last_identity"

    @MainActor
    static func handleIdentityChange(_ userId: String?) {
        let defaults = UserDefaults.standard
        let last = defaults.string(forKey: lastIdentityKey)

        switch (last, userId) {
        case (_, nil):
            // Signed out — private data leaves with the account.
            if last != nil {
                clearPrivateStores()
                defaults.removeObject(forKey: lastIdentityKey)
            }
        case (let last?, let new?) where last != new:
            // A different account on the same device — never show it the
            // previous account's gifting life.
            clearPrivateStores()
            defaults.set(new, forKey: lastIdentityKey)
        case (nil, let new?):
            // Guest data claimed by its first account.
            defaults.set(new, forKey: lastIdentityKey)
        default:
            break // same account back again
        }
    }

    @MainActor
    static func clearPrivateStores() {
        // A search history names the people and occasions you shop for.
        RecentSearchStore.shared.clear()
        // An invite belongs to a person, not to a phone — the next account on
        // this device starts locked out of Circles again.
        InviteAccess.shared.lock()
        PoolsStore.shared.clear()
        GroupGiftStore.shared.clear()
        SwipeListStore.shared.clear()
        ThoughtfulnessStore.shared.clear()
        // What you're buying, and the conversation about who you're buying it
        // for — both name the previous account's people.
        CartStore.shared.clear()
        MaxiConversationStore.shared.clear()
        // The view model holds the transcript in memory too — clearing only the
        // store would leave the previous account's conversation on screen.
        MaxiViewModel.shared.resetToGreeting()
        // Persona texts on the public profile editor.
        UserDefaults.standard.removeObject(forKey: "gifting_tagline")
        UserDefaults.standard.removeObject(forKey: "gifting_philosophy")
        UserDefaults.standard.removeObject(forKey: "gifting_showcase_synced")
        // Cached events (imported contacts' birthdays are PII) must not linger
        // for the next account on this device. Reads are already account-scoped,
        // but purge on the boundary too, for defense in depth.
        DataController.shared.clearAllData()
    }

    // Account DELETION: a hard clean slate. Everything clearPrivateStores wipes,
    // PLUS everything the app learned or was told about the user — the taste
    // profile, the cached vectors, the consult/onboarding answers, and the
    // SwiftData caches — so signing back in (even to the same provider account,
    // once the server row is deleted) starts genuinely fresh with nothing
    // carried over on-device.
    @MainActor
    static func wipeEverything(identity: String?) {
        clearPrivateStores()
        PersonalizationStore.clearAll(identity: identity)
        GiftingPrefs.clear()
        DataController.shared.clearAllData()
        UserDefaults.standard.removeObject(forKey: lastIdentityKey)
        Task {
            await TasteProfileStore.shared.clear()
            await VectorStore.shared.clear()
        }
    }
}
