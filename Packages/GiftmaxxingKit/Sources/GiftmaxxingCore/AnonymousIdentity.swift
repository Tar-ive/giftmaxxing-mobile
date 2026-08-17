import Foundation

// Stable anonymous identity so server-side taste accrues before signup and
// survives app restarts. A real signed-in user id takes precedence.
//
// It lives in Core because both the ranking queue and the API client need it,
// and neither should depend on the other. The key is a literal — moving this
// type between modules must never change it, or every anonymous user's history
// is orphaned.
public enum AnonymousIdentity {
    private static let key = "gm.anonUserId"

    public static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = "anon-" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }
}
