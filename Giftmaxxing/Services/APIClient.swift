import Foundation

actor APIClient {
    static let shared = APIClient()

    private let baseURL = "https://tvyu8gqmki.execute-api.us-east-1.amazonaws.com"
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

    func recordInteraction(userId: String, targetId: String, type: String, data: [String: String]? = nil) async {
        var body: [String: Any] = ["userId": userId, "targetId": targetId, "type": type]
        if let data { body["data"] = data }

        do {
            let _: EmptyResponse = try await post("/interactions", body: body)
        } catch {
            // fire-and-forget
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

        do {
            let reply: MaxiAgentReply = try await post("/maxi", body: body)
            return reply
        } catch {
            return nil
        }
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

    // MARK: - Graph

    func fetchGraph(userId: String) async throws -> GraphResponse {
        return try await get("/graph", params: ["userId": userId])
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
            price: p?.price ?? 0,
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
            reason: api.reason
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
