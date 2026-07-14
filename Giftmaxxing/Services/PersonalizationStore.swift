import Foundation

// Consult-derived personalization + per-identity onboarding state.
//
// Two jobs:
//  1. Persist the signals the concierge learns about the USER (genderPref,
//     world vibes) so the feed's candidate fetch can use them immediately —
//     this is the cold-start personalization the on-device ranker can't do
//     with zero interactions.
//  2. Track "has onboarded" PER IDENTITY (guest / each signed-in account).
//     The old single `hasSeenOnboarding` bool was device-global, which is
//     why a brand-new Google account never saw onboarding.
enum PersonalizationStore {
    private static let genderKey = "consult.genderPref"
    private static let vibesKey = "consult.vibes"
    private static let onboardedPrefix = "onboarded."
    private static let legacyKey = "hasSeenOnboarding"

    // MARK: - Consult signals

    static var genderPref: String? {
        get { UserDefaults.standard.string(forKey: genderKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: genderKey)
            } else {
                UserDefaults.standard.removeObject(forKey: genderKey)
            }
        }
    }

    static var consultVibes: [String] {
        get { UserDefaults.standard.stringArray(forKey: vibesKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(6)), forKey: vibesKey) }
    }

    // Self-taste interview (Edit taste / Maxi trivia) — used by friends buying for you.
    private static let styleKey = "taste.giftStyle"
    private static let dislikesKey = "taste.dislikes"
    private static let noteKey = "taste.giftNote"
    private static let sizesKey = "taste.clothingSizes"

    static var giftStyle: String? {
        get { UserDefaults.standard.string(forKey: styleKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: styleKey)
            } else {
                UserDefaults.standard.removeObject(forKey: styleKey)
            }
        }
    }

    static var dislikes: [String] {
        get { UserDefaults.standard.stringArray(forKey: dislikesKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: dislikesKey) }
    }

    static var giftNote: String? {
        get { UserDefaults.standard.string(forKey: noteKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: noteKey)
            } else {
                UserDefaults.standard.removeObject(forKey: noteKey)
            }
        }
    }

    static var clothingSizes: [String: String]? {
        get { UserDefaults.standard.dictionary(forKey: sizesKey) as? [String: String] }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: sizesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: sizesKey)
            }
        }
    }

    // genderPref → the catalog's recipient facet (soft boost on GET /feed).
    static var feedRecipient: String? {
        switch genderPref {
        case "him": return "men"
        case "her": return "women"
        default: return nil
        }
    }

    // MARK: - Per-identity onboarding

    private static func key(for identity: String?) -> String {
        onboardedPrefix + (identity ?? "guest")
    }

    static func hasOnboarded(identity: String?) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: identity))
    }

    static func markOnboarded(identity: String?) {
        UserDefaults.standard.set(true, forKey: key(for: identity))
        // Keep the legacy flag in sync for anything still reading it.
        UserDefaults.standard.set(true, forKey: legacyKey)
    }

    // One-time migration: devices that dismissed the OLD onboarding keep that
    // dismissal for the GUEST identity only — signed-in accounts still get
    // their own first-run consult.
    static func migrateLegacyFlagIfNeeded() {
        if UserDefaults.standard.bool(forKey: legacyKey), !hasOnboarded(identity: nil) {
            UserDefaults.standard.set(true, forKey: key(for: nil))
        }
    }

    // Account deletion: erase everything the concierge learned about the user —
    // consult signals, the self-taste interview, and the onboarded flags for
    // this identity (and guest), so a re-sign-in starts truly fresh.
    static func clearAll(identity: String?) {
        let d = UserDefaults.standard
        for k in [genderKey, vibesKey, styleKey, dislikesKey, noteKey, sizesKey, legacyKey] {
            d.removeObject(forKey: k)
        }
        d.removeObject(forKey: key(for: identity))
        d.removeObject(forKey: key(for: nil))
    }
}
