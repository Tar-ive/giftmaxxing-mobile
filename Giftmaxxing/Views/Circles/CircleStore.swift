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

    // The circle page lives on the NEW web app (giftmaxxing-web), not the
    // legacy hackathon site InviteLink.siteURL still points at — /circle/<id>
    // only exists there.
    static let webOrigin = "https://giftmaxxing-web.vercel.app"

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
