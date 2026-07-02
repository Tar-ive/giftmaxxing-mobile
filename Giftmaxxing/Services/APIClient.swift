import Foundation

actor APIClient {
    static let shared = APIClient()

    // CloudFront edge cache in front of the API (infra/cloudfront.tf). Generic
    // feed pages + /vectors are served from cache; personal routes pass through.
    // (Old direct origin: https://tvyu8gqmki.execute-api.us-east-1.amazonaws.com)
    private let baseURL = "https://d21osnvwewgoao.cloudfront.net"
    private let session: URLSession
    private let decoder: JSONDecoder

    private var authToken: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
    }

    func setAuthToken(_ token: String?) {
        authToken = token
    }

    // MARK: - Feed

    func fetchFeed(
        cursor: String? = nil,
        limit: Int = 20,
        vibes: [String]? = nil,
        recipient: String? = nil,
        occasion: String? = nil,
        category: String? = nil,
        budget: Double? = nil,
        userId: String? = nil
    ) async throws -> FeedPage {
        var params: [String: String] = [:]
        if let cursor { params["cursor"] = cursor }
        params["limit"] = String(limit)
        if let vibes, !vibes.isEmpty { params["vibes"] = vibes.joined(separator: ",") }
        if let recipient { params["recipient"] = recipient }
        if let occasion { params["occasion"] = occasion }
        if let category { params["category"] = category }
        if let budget { params["budget"] = String(budget) }
        if let userId { params["userId"] = userId }

        let response: FeedResponse = try await get("/feed", params: params)
        let posts = (response.items ?? []).map { mapAPIPost($0) }
        return FeedPage(posts: posts, cursor: response.cursor)
    }

    func fetchRecommendations(
        cursor: String? = nil,
        limit: Int = 20,
        vibes: [String]? = nil,
        userId: String? = nil
    ) async throws -> FeedPage {
        var params: [String: String] = [:]
        if let cursor { params["cursor"] = cursor }
        params["limit"] = String(limit)
        if let vibes, !vibes.isEmpty { params["vibes"] = vibes.joined(separator: ",") }
        if let userId { params["userId"] = userId }

        let response: FeedResponse = try await get("/recommendations", params: params)
        let posts = (response.items ?? []).map { mapAPIPost($0) }
        return FeedPage(posts: posts, cursor: response.cursor)
    }

    // MARK: - Interactions

    func recordInteraction(userId: String?, targetId: String, type: String, data: [String: String]? = nil) async {
        var body: [String: Any] = ["targetId": targetId, "type": type]
        if let userId { body["userId"] = userId }
        if let data { body["data"] = data }

        do {
            let _: EmptyResponse = try await post("/interactions", body: body)
        } catch {
            // fire-and-forget
        }
    }

    func batchRecordInteractions(_ interactions: [[String: Any]]) async {
        guard !interactions.isEmpty else { return }
        let body: [String: Any] = ["interactions": interactions]
        do {
            let _: EmptyResponse = try await post("/mobile/interactions/batch", body: body)
        } catch {
            // fall back to individual calls
            for interaction in interactions {
                await recordInteraction(
                    userId: interaction["userId"] as? String,
                    targetId: interaction["targetId"] as? String ?? "",
                    type: interaction["type"] as? String ?? ""
                )
            }
        }
    }

    func fetchInteractions(userId: String, types: [String]? = nil) async throws -> [PersistedInteraction] {
        var params: [String: String] = ["userId": userId]
        if let types, !types.isEmpty { params["types"] = types.joined(separator: ",") }
        let response: InteractionsResponse = try await get("/interactions", params: params)
        return response.items ?? []
    }

    // MARK: - User Profile

    func fetchMe(userId: String) async throws -> UserProfile? {
        let response: UserProfileResponse = try await get("/me", params: ["userId": userId])
        return response.item
    }

    func saveMe(userId: String, profile: UserProfile) async throws {
        let body: [String: Any] = ["userId": userId, "profile": encodeToDictionary(profile)]
        let _: EmptyResponse = try await put("/me", body: body)
    }

    func saveMe(userId: String, profile: [String: String]) async throws {
        var body: [String: Any] = ["userId": userId]
        body["profile"] = profile
        let _: EmptyResponse = try await put("/me", body: body)
    }

    // MARK: - Events

    func fetchUpcomingEvents(userId: String, withinDays: Int = 90) async throws -> [UpcomingEvent] {
        let params: [String: String] = [
            "userId": userId,
            "withinDays": String(withinDays)
        ]
        let response: UpcomingEventsResponse = try await get("/events/upcoming", params: params)
        return response.items ?? []
    }

    // MARK: - Maxi Agent

    func askMaxi(userId: String?, name: String?, message: String, history: [(role: String, text: String)]) async throws -> MaxiAgentReply? {
        var body: [String: Any] = ["message": message]
        if let userId { body["userId"] = userId }
        if let name { body["name"] = name }
        if !history.isEmpty {
            let msgs = history.suffix(12).map { ["role": $0.role, "text": $0.text] }
            body["messages"] = msgs
        }

        // Throws so the caller can tell 401 (sign-in needed) from 429/503
        // (budget guard) from network loss — each gets different fallback UX.
        let reply: MaxiAgentReply = try await post("/maxi", body: body)
        return reply
    }

    // MARK: - Vector Recommendations

    func fetchVectorRecommendations(
        seedKeys: [String]? = nil,
        vibes: [String]? = nil,
        sourceUser: String? = nil,
        limit: Int = 12
    ) async throws -> VectorResponse {
        var params: [String: String] = ["limit": String(limit)]
        if let seedKeys, !seedKeys.isEmpty { params["seedKeys"] = seedKeys.joined(separator: ",") }
        if let vibes, !vibes.isEmpty { params["vibes"] = vibes.joined(separator: ",") }
        if let sourceUser { params["sourceUser"] = sourceUser }

        return try await get("/recommendations", params: params)
    }

    // Visual search: query image -> Titan MM embed -> kNN over S3 Vectors.
    // Mirrors web fetchVisualSearch (POST /visual-search {imageBase64, ...}).
    func fetchVisualSearch(imageBase64: String, text: String? = nil, limit: Int = 18) async throws -> VectorResponse {
        var body: [String: Any] = ["imageBase64": imageBase64, "limit": limit]
        if let text, !text.isEmpty { body["text"] = text }
        return try await post("/visual-search", body: body)
    }

    // MARK: - On-device ranking support

    // Quantized Titan embeddings for a set of pin keys — feeds the on-device
    // VectorStore so centroid + similarity math runs locally instead of in the
    // Lambda (GET /vectors is served straight from S3 Vectors GetVectors).
    func fetchVectors(keys: [String]) async throws -> VectorsResponse {
        guard !keys.isEmpty else { return VectorsResponse(items: [], source: nil) }
        return try await get("/vectors", params: ["keys": keys.prefix(60).joined(separator: ",")])
    }

    // Batched interaction upload (one Lambda invocation per batch instead of
    // one per tap). Server accepts { items: [...] } on POST /interactions.
    func sendInteractionsBatch(_ batch: [InteractionQueue.PendingInteraction]) async throws {
        guard !batch.isEmpty else { return }
        let items: [[String: Any]] = batch.map {
            ["userId": $0.userId, "targetId": $0.targetId, "type": $0.type, "createdAt": Int($0.queuedAt * 1000)]
        }
        let _: EmptyResponse = try await post("/interactions", body: ["items": items])
    }

    // MARK: - Connections (swipe-challenge responses; auth-gated server-side)

    func fetchConnections(userId: String, unseenOnly: Bool = false) async throws -> [SoftConnectionItem] {
        var params: [String: String] = ["userId": userId]
        if unseenOnly { params["unseenOnly"] = "1" }
        let response: ConnectionsResponse = try await get("/connections", params: params)
        return (response.items ?? []).sorted { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) }
    }

    // MARK: - Graph

    func fetchGraph(userId: String) async throws -> GraphResponse {
        return try await get("/graph", params: ["userId": userId])
    }

    // MARK: - Mobile Device Registration

    func registerDevice(userId: String, platform: String, token: String) async throws {
        let body: [String: Any] = [
            "userId": userId,
            "platform": platform,
            "token": token,
        ]
        let _: EmptyResponse = try await post("/mobile/device", body: body)
    }

    // MARK: - Delta Sync

    func fetchDeltaSync(since: Date) async throws -> DeltaSyncResponse {
        let params: [String: String] = [
            "since": String(Int(since.timeIntervalSince1970 * 1000)),
        ]
        return try await get("/mobile/sync", params: params)
    }

    // MARK: - Analytics

    func uploadAnalytics(events: [[String: Any]]) async throws {
        let body: [String: Any] = ["events": events]
        let _: EmptyResponse = try await post("/mobile/analytics", body: body)
    }

    // MARK: - Raw execution (for offline queue replay)

    func executeRaw(method: String, path: String, body: [String: Any]?) async throws {
        switch method.uppercased() {
        case "POST":
            let _: EmptyResponse = try await post(path, body: body ?? [:])
        case "PUT":
            let _: EmptyResponse = try await put(path, body: body ?? [:])
        default:
            let _: EmptyResponse = try await get(path)
        }
    }

    // MARK: - Networking

    private func get<T: Decodable>(_ path: String, params: [String: String] = [:]) async throws -> T {
        var components = URLComponents(string: baseURL + path)!
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuth(&request)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        applyAuth(&request)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }

    private func put<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        applyAuth(&request)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        return try decoder.decode(T.self, from: data)
    }

    private func applyAuth(_ request: inout URLRequest) {
        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    private func encodeToDictionary<T: Encodable>(_ value: T) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(value),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    // MARK: - Post Mapping

    private func mapAPIPost(_ api: APIPost) -> Post {
        let p = api.product
        let product = Product(
            id: p?.id ?? api.postId,
            name: p?.name ?? api.caption ?? "Gift find",
            brand: p?.brand ?? api.source ?? "Reddit",
            price: p?.price ?? api.price ?? 0,
            grad: GradientStyle(rawValue: p?.grad ?? "peach") ?? .peach,
            emoji: p?.emoji ?? "🎁",
            image: p?.image
        )

        return Post(
            id: api.postId,
            user: api.author ?? "reddit",
            time: relativeTime(ms: api.createdAt),
            product: product,
            caption: api.caption ?? "",
            likes: api.likes ?? 0,
            liked: false,
            saved: false,
            comments: [],
            commentCount: api.comments,
            source: api.source,
            url: api.url,
            productUrl: api.productUrl,
            rec: api.rec,
            reason: api.reason,
            recipient: api.recipient,
            occasion: api.occasion,
            category: api.category,
            domain: api.domain ?? api.merchant,
            qualityScore: api.qualityScore,
            feedEligible: api.feedEligible
        )
    }

    private func relativeTime(ms: Double?) -> String {
        guard let ms else { return "" }
        let seconds = max(1, Int((Date().timeIntervalSince1970 * 1000 - ms) / 1000))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 365 { return "\(days)d" }
        return "\(days / 365)y"
    }
}

struct FeedPage {
    var posts: [Post]
    var cursor: String?
}

struct EmptyResponse: Decodable {}

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "Server returned status \(code)"
        }
    }
}
