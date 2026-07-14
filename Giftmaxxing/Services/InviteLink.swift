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
    // Server-side challenge (POST /challenges): when present, the guest page
    // fetches the pre-built deck from GET /challenges/{id} and posts swipes to
    // /challenges/{id}/response — deck + verdict fully server-side. Absent →
    // the legacy local-deck flow (old links keep working).
    var challengeId: String?
    var pool: PoolInviteSnapshot?
}

struct PoolInviteSnapshot: Codable {
    var id: String
    var title: String
    var occasion: String
    var goal: Double
    var image: String?
}

enum InviteLink {
    // Canonical public web origin (web/.env NEXT_PUBLIC_SITE_URL equivalent):
    // the giftmaxxing-web deployment serving this repo's web/ app, which knows
    // how to handle server-side challengeId links.
    static let siteURL = "https://giftmaxxing-web.vercel.app"

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
        date: String? = nil,
        challengeId: String? = nil
    ) -> URL? {
        var payload = InvitePayload(name: inviterName.trimmingCharacters(in: .whitespaces))
        if payload.name.isEmpty { payload.name = "A friend" }
        payload.senderId = senderId
        if let to = to?.trimmingCharacters(in: .whitespaces), !to.isEmpty { payload.to = to }
        if let occasion, !occasion.isEmpty { payload.occasion = occasion }
        if let date, !date.isEmpty { payload.date = date }
        if let challengeId, !challengeId.isEmpty { payload.challengeId = challengeId }
        guard let code = encode(payload) else { return nil }
        return URL(string: "\(siteURL)/invite/\(code)")
    }

    static func buildPoolURL(inviterName: String, pool: Pool) -> URL? {
        var payload = InvitePayload(name: inviterName.trimmingCharacters(in: .whitespaces))
        if payload.name.isEmpty { payload.name = "A friend" }
        payload.pool = PoolInviteSnapshot(
            id: pool.id,
            title: pool.title,
            occasion: pool.occasion ?? "",
            goal: pool.targetAmount,
            image: nil
        )
        guard let code = encode(payload) else { return nil }
        return URL(string: "\(siteURL)/invite/\(code)")
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // ── In-app opening (the reverse direction) ────────────────────────────
    // App users who receive an invite shouldn't be bounced to the browser:
    // decode the payload back out of a shared link so the native swipe deck
    // (ChallengeSwipeView) can open right here.

    static func decodePayload(fromURL url: URL) -> InvitePayload? {
        let components = url.pathComponents
        guard let inviteIndex = components.firstIndex(of: "invite"),
              components.count > inviteIndex + 1 else { return nil }
        var code = components[inviteIndex + 1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while code.count % 4 != 0 { code += "=" }
        guard let data = Data(base64Encoded: code) else { return nil }
        return try? JSONDecoder().decode(InvitePayload.self, from: data)
    }

    // A server-side challenge id from any invite-shaped URL:
    // giftmaxxing://challenge/<id> or <site>/invite/<base64url payload>.
    static func challengeId(fromURL url: URL) -> String? {
        if url.scheme == "giftmaxxing", url.host == "challenge" {
            let id = url.pathComponents.last(where: { $0 != "/" })
            return (id?.isEmpty ?? true) ? nil : id
        }
        return decodePayload(fromURL: url)?.challengeId
    }
}
