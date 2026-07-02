import Foundation

// Builds shareable swipe-challenge links with the SAME wire format as the web
// app (web/lib/invite.ts): base64url-encoded JSON payload in the URL path,
// decoded by the public /invite/[code] page. The recipient always lands in the
// mobile BROWSER (zero-friction guest swipe — no account, no install), and the
// completed challenge posts back to the sender via the public POST /connections.
//
// Sender identity mirrors the web's boundary: the signed-in user id when we
// have one, else the device's stable anonymous id — responses collected under
// the anon id are re-keyed onto the real account on sign-in (POST
// /connections/claim, same claim flow the web AccountSync uses).

struct InvitePayload: Codable {
    var name: String
    var senderId: String?
    var to: String?
    var occasion: String?
    var date: String?
}

enum InviteLink {
    // Canonical public web origin (web/.env NEXT_PUBLIC_SITE_URL equivalent).
    static let siteURL = "https://giftmaxxing.vercel.app"

    static let shareText =
        "Would you want this gifted to you? 👀 Swipe to find your gift taste on Giftmaxxing"

    static func encode(_ payload: InvitePayload) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return nil }
        return base64url(data)
    }

    // The shareable URL: <site>/invite/<base64url(JSON payload)>.
    static func buildURL(
        inviterName: String,
        senderId: String?,
        to: String? = nil,
        occasion: String? = nil,
        date: String? = nil
    ) -> URL? {
        var payload = InvitePayload(name: inviterName.trimmingCharacters(in: .whitespaces))
        if payload.name.isEmpty { payload.name = "A friend" }
        payload.senderId = senderId
        if let to = to?.trimmingCharacters(in: .whitespaces), !to.isEmpty { payload.to = to }
        if let occasion, !occasion.isEmpty { payload.occasion = occasion }
        if let date, !date.isEmpty { payload.date = date }
        guard let code = encode(payload) else { return nil }
        return URL(string: "\(siteURL)/invite/\(code)")
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
