import Foundation

// Which circles this device belongs to (and as whom) — the iOS twin of the
// web's localStorage "giftmaxxing_my_circles" (web/lib/circles.ts). Server
// truth for a circle's contents lives under GET /circles/{id}; this store only
// remembers membership so the Circles tab can list yours across launches.
struct MyCircle: Identifiable, Codable {
    let circleId: String
    var name: String
    var emoji: String?
    var joinedAs: String? // the name you entered when creating/joining
    var savedAt: Date

    var id: String { circleId }
}

@MainActor
final class CircleStore: ObservableObject {
    static let shared = CircleStore()

    @Published private(set) var circles: [MyCircle] = []

    private static let storageKey = "giftmaxxing_my_circles"

    // Same giftmaxxing-web origin as InviteLink.siteURL — /circle/<id> lives
    // on this repo's web app.
    static let webOrigin = InviteLink.siteURL

    init() {
        load()
    }

    static func shareURL(circleId: String) -> URL? {
        URL(string: "\(webOrigin)/circle/\(circleId)")
    }

    // Pull a circle id out of anything shareable: giftmaxxing://circle/<id>
    // (host is "circle") or https://<any-host>/circle/<id>. A "circle" path
    // segment is required — substrings like ".../product/cir_notacircle"
    // must not hijack routing.
    static func circleId(fromURL url: URL) -> String? {
        guard url.host == "circle" || url.pathComponents.contains("circle") else { return nil }
        return circleId(fromText: url.absoluteString)
    }

    static func circleId(fromText text: String) -> String? {
        if let range = text.range(of: #"cir_[A-Za-z0-9\-]+"#, options: .regularExpression) {
            return String(text[range])
        }
        return nil
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([MyCircle].self, from: data) {
            circles = saved
        }
    }

    func remember(circleId: String, name: String, emoji: String?, joinedAs: String?) {
        circles.removeAll { $0.circleId == circleId }
        circles.insert(
            MyCircle(circleId: circleId, name: name, emoji: emoji, joinedAs: joinedAs, savedAt: Date()),
            at: 0
        )
        circles = Array(circles.prefix(20))
        persist()
    }

    /// Pull server-side membership (circles someone ADDED you to) and merge it
    /// into the device list. Without this, being added by a friend would be
    /// invisible here — membership used to be device-local only.
    func syncFromServer(userId: String?) async {
        guard let userId, !userId.isEmpty,
              let remote = try? await APIClient.shared.listMyCircles(userId: userId)
        else { return }
        var changed = false
        for ref in remote where !circles.contains(where: { $0.circleId == ref.circleId }) {
            circles.append(MyCircle(
                circleId: ref.circleId,
                name: ref.name,
                emoji: ref.emoji,
                joinedAs: nil,
                savedAt: ref.joinedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
            ))
            changed = true
        }
        if changed { persist() }
    }

    func forget(_ circleId: String) {
        circles.removeAll { $0.circleId == circleId }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(circles) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
