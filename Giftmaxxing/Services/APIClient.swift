import Foundation

actor APIClient {
    static let shared = APIClient()

    // CloudFront edge cache in front of the API (infra/cloudfront.tf). Generic
    // feed pages + /vectors are served from cache; personal routes pass through.
    // (Old direct origin: https://tvyu8gqmki.execute-api.us-east-1.amazonaws.com)
    private let baseURL = "https://d21osnvwewgoao.cloudfront.net"
    private let session: URLSession
    private let uploadSession: URLSession
    private let decoder: JSONDecoder

    private var authToken: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)

        let uploadConfig = URLSessionConfiguration.default
        uploadConfig.timeoutIntervalForRequest = 120
        uploadConfig.timeoutIntervalForResource = 15 * 60
        uploadSession = URLSession(configuration: uploadConfig)

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
    }

    func setAuthToken(_ token: String?) {
        authToken = token
    }

    // MARK: - User-generated posts

    func createUGCUpload(
        mediaType: String,
        mimeType: String,
        fileSize: Int,
        caption: String
    ) async throws -> UGCUploadResponse {
        try await post("/ugc/uploads", body: [
            "mediaType": mediaType,
            "mimeType": mimeType,
            "fileSize": fileSize,
            "caption": caption,
        ])
    }

    func uploadUGC(fileURL: URL, to uploadURL: String, headers: [String: String]) async throws {
        guard let url = URL(string: uploadURL) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (_, response) = try await uploadSession.upload(for: request, fromFile: fileURL)
        try validateResponse(response)
    }

    func completeUGCUpload(postId: String) async throws {
        let _: UGCCompleteResponse = try await post("/ugc/posts/\(postId)/complete", body: [:])
    }

    func fetchMyUGCPosts() async throws -> [UGCPost] {
        let response: UGCPostsResponse = try await get("/ugc/posts")
        return response.items.map(normalizeUGCPost)
    }

    func fetchUGCPost(postId: String) async throws -> UGCPost {
        let response: UGCPostResponse = try await get("/ugc/posts/\(postId)")
        return normalizeUGCPost(response.item)
    }

    func reportUGCPost(postId: String, reason: String) async throws {
        let _: EmptyResponse = try await post("/ugc/posts/\(postId)/report", body: ["reason": reason])
    }

    func blockUGCUser(userId: String) async throws {
        let _: EmptyResponse = try await post("/ugc/users/\(userId)/block", body: [:])
    }

    func createAvatarUpload(mimeType: String, fileSize: Int) async throws -> AvatarUploadResponse {
        try await post("/ugc/avatar/uploads", body: ["mimeType": mimeType, "fileSize": fileSize])
    }

    func uploadAvatar(data: Data, to uploadURL: String, headers: [String: String]) async throws {
        guard let url = URL(string: uploadURL) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (_, response) = try await uploadSession.upload(for: request, from: data)
        try validateResponse(response)
    }

    func completeAvatarUpload(avatarId: String) async throws -> String {
        let response: AvatarCompleteResponse = try await post("/ugc/avatar/uploads/\(avatarId)/complete", body: [:])
        return absoluteMediaURL(response.imageUrl) ?? response.imageUrl
    }

    func removeAvatar() async throws {
        let _: EmptyResponse = try await delete("/ugc/avatar")
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
        userId: String? = nil,
        cacheBuster: String? = nil
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
        // Feed pages are CloudFront-cached BY URL (that's the scaling design),
        // so an identical request returns the identical page. Two dials keep
        // content fresh without giving up the shared cache:
        //   d = UTC day bucket, ALWAYS sent — pages stay shared across users
        //       within a day but roll over at midnight, so newly ingested
        //       inventory (e.g. the Shopify catalog) reaches everyone within
        //       24h even if their exact URL variant was cached earlier.
        //   r = unique per pull-to-refresh — an immediate cache miss + a new
        //       server random-seek. Never sent on scroll pagination.
        params["d"] = Self.dailyFeedBucket
        if let cacheBuster { params["r"] = cacheBuster }

        let response: FeedResponse = try await get("/feed", params: params)
        let posts = (response.items ?? []).map { mapAPIPost($0) }
        return FeedPage(posts: posts, cursor: response.cursor)
    }

    static var dailyFeedBucket: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }

    func fetchRecommendations(
        cursor: String? = nil,
        limit: Int = 20,
        vibes: [String]? = nil,
        recipient: String? = nil,
        userId: String? = nil
    ) async throws -> FeedPage {
        var params: [String: String] = [:]
        if let cursor { params["cursor"] = cursor }
        params["limit"] = String(limit)
        if let vibes, !vibes.isEmpty { params["vibes"] = vibes.joined(separator: ",") }
        if let recipient { params["recipient"] = recipient }
        if let userId { params["userId"] = userId }

        let response: FeedResponse = try await get("/recommendations", params: params)
        let posts = (response.items ?? []).map { mapAPIPost($0) }
        return FeedPage(posts: posts, cursor: response.cursor)
    }

    // MARK: - Curated galleries + gift bundles

    // Server-curated gallery membership (CONFIG gallery#<id>, built by
    // infra/ingest/build-shelves.mjs — semantic kNN over the shelf theme, not
    // vibe keywords). Throws (incl. 404) when no curated list exists yet; the
    // caller falls back to the legacy query-by-vibes path.
    func fetchGallery(id: String, limit: Int = 60) async throws -> [Post] {
        let response: FeedResponse = try await get("/galleries/\(id)", params: ["limit": String(limit)])
        return (response.items ?? []).map { mapAPIPost($0) }
    }

    struct GiftBundleSlot: Identifiable {
        let id: String
        let label: String
        let emoji: String
        let items: [Post]
    }
    struct GiftBundle: Identifiable {
        let id: String
        let recipient: String
        let why: String
        let slots: [GiftBundleSlot]
    }

    // Reddit-mined "goes together" bundles resolved to buyable products.
    // recipient nil -> sampler across all mined recipients.
    func fetchGiftBundles(recipient: String? = nil, limit: Int = 6) async throws -> [GiftBundle] {
        struct SlotDTO: Codable { let key: String?; let label: String?; let emoji: String?; let items: [APIPost]? }
        struct BundleDTO: Codable { let recipient: String?; let why: String?; let slots: [SlotDTO]? }
        struct BundlesResponse: Codable { let bundles: [BundleDTO]? }
        var params = ["limit": String(limit)]
        if let recipient { params["recipient"] = recipient }
        let response: BundlesResponse = try await get("/bundles", params: params)
        return (response.bundles ?? []).enumerated().map { i, b in
            GiftBundle(
                id: "\(b.recipient ?? "any")-\(i)",
                recipient: b.recipient ?? "anyone",
                why: b.why ?? "Often gifted together",
                slots: (b.slots ?? []).map { s in
                    GiftBundleSlot(
                        id: s.key ?? s.label ?? UUID().uuidString,
                        label: s.label ?? "Gift",
                        emoji: s.emoji ?? "🎁",
                        items: (s.items ?? []).map { mapAPIPost($0) }
                    )
                }
            )
        }
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

    // POST /auth/session — trade the (short-lived) provider ID token currently
    // set as the bearer for a 30-day first-party session JWT. The returned
    // userId is the CANONICAL identity: if this email already has an account
    // (e.g. created on the web), that account's id comes back and the app
    // adopts it — the web → iOS "all my data is here" handshake.
    struct SessionResponse: Codable {
        let token: String
        let userId: String
        let email: String?
        let expiresIn: Double?
    }

    func establishSession(name: String? = nil) async throws -> SessionResponse {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        return try await post("/auth/session", body: body)
    }

    // POST /me/identity — name/email ping that MERGES server-side. Never use
    // PUT /me for sign-in pings: that REPLACES the row and wipes the profile
    // the web app saved (interests, events, genderPref …).
    func identify(userId: String, name: String? = nil, email: String? = nil) async {
        var body: [String: Any] = ["userId": userId]
        if let name, !name.isEmpty { body["name"] = name }
        if let email, !email.isEmpty { body["email"] = email }
        let _: EmptyResponse? = try? await post("/me/identity", body: body)
    }

    func fetchMe(userId: String) async throws -> UserProfile? {
        let response: UserProfileResponse = try await get("/me", params: ["userId": userId])
        var profile = response.item
        let imageUrl = profile?.imageUrl
        profile?.imageUrl = absoluteMediaURL(imageUrl)
        if let showcase = profile?.giftShowcase {
            profile?.giftShowcase = showcase.map { item in
                var item = item
                item.imageUrl = absoluteMediaURL(item.imageUrl)
                return item
            }
        }
        return profile
    }

    // DELETE /account — App Store 5.1.1(v). Permanently deletes the signed-in
    // user's account and all server-side data (profile, interactions, soft
    // profiles, events, graph, friend edges). Irreversible.
    func deleteAccount(userId: String) async throws {
        let _: EmptyResponse = try await delete("/account", params: ["userId": userId])
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

    // PUT /me with an arbitrary payload — the web app's profile shape is a
    // superset of our Codable UserProfile, so the concierge writes the full
    // web-compatible dictionary. PUT REPLACES the row: callers must only use
    // this when the account has no completed profile yet.
    func saveMeRaw(userId: String, profile: [String: Any]) async throws {
        let body: [String: Any] = ["userId": userId, "profile": profile]
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

    // GET /events — the unified events table (user-added dates, scope-tagged).
    // Distinct from /events/upcoming, which reads onboarding-logged occasions
    // off the user profile; the Circles hub merges both.
    func fetchEvents(userId: String, scope: String? = nil) async throws -> [UpcomingEvent] {
        var params: [String: String] = ["userId": userId]
        if let scope { params["scope"] = scope }
        let response: UpcomingEventsResponse = try await get("/events", params: params)
        return response.items ?? []
    }

    // MARK: - Circles (web/lib/circles.ts parity)
    // A circle is a shared family/friend group: members add their name +
    // birthday via the /circle/<id> web link (no account), and everyone sees
    // one gift calendar. The link is the credential.

    func createCircle(name: String, emoji: String?, creatorName: String?, creatorBirthday: String?) async throws -> CircleCreateResponse {
        var body: [String: Any] = ["name": name]
        if let emoji, !emoji.isEmpty { body["emoji"] = emoji }
        if let creatorName, !creatorName.isEmpty {
            var creator: [String: Any] = ["name": creatorName]
            if let creatorBirthday, !creatorBirthday.isEmpty { creator["birthday"] = creatorBirthday }
            body["creator"] = creator
        }
        return try await post("/circles", body: body)
    }

    func fetchCircle(circleId: String) async throws -> CircleDataResponse {
        try await get("/circles/\(circleId)")
    }

    func joinCircle(circleId: String, name: String, birthday: String?, userId: String? = nil) async throws -> CircleJoinResponse {
        var body: [String: Any] = ["name": name]
        if let birthday, !birthday.isEmpty { body["birthday"] = birthday }
        if let userId, !userId.isEmpty { body["userId"] = userId }
        return try await post("/circles/\(circleId)/join", body: body)
    }

    /// Link a signed-in account to a circle seat so other members can friend / message / gift you.
    @discardableResult
    func claimCircleSeat(circleId: String, userId: String, memberName: String) async throws -> CircleClaimResponse {
        try await post(
            "/circles/\(circleId)/claim",
            body: ["userId": userId, "memberName": memberName]
        )
    }

    // MARK: - Friends / people discovery / DMs

    func searchPeople(query: String = "", limit: Int = 24) async throws -> [PublicPerson] {
        var params: [String: String] = ["limit": String(limit)]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { params["q"] = trimmed }
        let response: PeopleSearchResponse = try await get("/people", params: params)
        return (response.items ?? []).map(normalizePerson)
    }

    func fetchPerson(userId: String) async throws -> PublicPerson? {
        let response: PersonResponse = try await get("/people/\(userId)")
        return response.item.map(normalizePerson)
    }

    func listFriends(userId: String, status: String? = nil) async throws -> [Friendship] {
        var params: [String: String] = ["userId": userId]
        if let status { params["status"] = status }
        let response: FriendsListResponse = try await get("/friends", params: params)
        return response.items ?? []
    }

    func friendshipStatus(userId: String, otherId: String) async throws -> FriendshipStatusResponse {
        try await get("/friends/status", params: ["userId": userId, "otherId": otherId])
    }

    @discardableResult
    func requestFriend(fromUserId: String, toUserId: String, circleId: String? = nil) async throws -> FriendActionResponse {
        var body: [String: Any] = ["fromUserId": fromUserId, "toUserId": toUserId]
        if let circleId { body["circleId"] = circleId }
        return try await post("/friends/request", body: body)
    }

    @discardableResult
    func acceptFriend(userId: String, fromUserId: String) async throws -> FriendActionResponse {
        try await post("/friends/accept", body: ["userId": userId, "fromUserId": fromUserId])
    }

    @discardableResult
    func removeFriend(userId: String, friendId: String) async throws -> FriendActionResponse {
        try await post("/friends/remove", body: ["userId": userId, "fromUserId": friendId, "friendId": friendId])
    }

    func openDm(userId: String, otherUserId: String) async throws -> String {
        let response: DmOpenResponse = try await post(
            "/dms/open",
            body: ["userId": userId, "otherUserId": otherUserId]
        )
        guard let threadId = response.threadId else {
            throw APIError.invalidResponse
        }
        return threadId
    }

    func listDms(userId: String) async throws -> [DmThread] {
        let response: DmListResponse = try await get("/dms", params: ["userId": userId])
        return response.items ?? []
    }

    func fetchDmMessages(threadId: String) async throws -> [DmMessage] {
        let encoded = threadId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? threadId
        let response: DmMessagesResponse = try await get("/dms/\(encoded)/messages")
        return response.items ?? []
    }

    @discardableResult
    func sendDmMessage(threadId: String, userId: String, name: String, text: String) async throws -> DmMessage {
        let encoded = threadId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? threadId
        let response: DmSendResponse = try await post(
            "/dms/\(encoded)/messages",
            body: ["userId": userId, "name": name, "text": text]
        )
        guard let message = response.message else {
            throw APIError.invalidResponse
        }
        return message
    }

    @discardableResult
    func addCircleEvent(
        circleId: String,
        title: String,
        date: String,
        type: String? = nil,
        forName: String? = nil,
        addedBy: String? = nil
    ) async throws -> CircleAck {
        var body: [String: Any] = ["title": title, "date": date]
        if let type, !type.isEmpty { body["type"] = type }
        if let forName, !forName.isEmpty { body["forName"] = forName }
        if let addedBy, !addedBy.isEmpty { body["addedBy"] = addedBy }
        return try await post("/circles/\(circleId)/events", body: body)
    }

    @discardableResult
    func deleteCircleEvent(circleId: String, eventId: String) async throws -> CircleAck {
        try await post("/circles/\(circleId)/events/delete", body: ["eventId": eventId])
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
        userId: String? = nil,
        limit: Int = 12,
        rank: String? = nil,
        cacheBuster: String? = nil
    ) async throws -> VectorResponse {
        var params: [String: String] = ["limit": String(limit)]
        if let seedKeys, !seedKeys.isEmpty { params["seedKeys"] = seedKeys.joined(separator: ",") }
        if let vibes, !vibes.isEmpty { params["vibes"] = vibes.joined(separator: ",") }
        if let sourceUser { params["sourceUser"] = sourceUser }
        // userId alone is enough: the server seeds the taste centroid from the
        // user's own interaction history (likes/saves) when no seedKeys given.
        if let userId, !userId.isEmpty { params["userId"] = userId }
        // Interaction model: nil/"fast" -> instant cosine order (front-end
        // path); "full" -> MTL value-model re-rank (intelligent back-end
        // path, called after first paint — may take seconds on a cold start).
        if let rank { params["rank"] = rank }
        // Personalized recommendations are also behind CloudFront. A pull
        // must use a new URL so a prior response cannot mask fresh interaction
        // signals or a newly generated vector ranking.
        if let cacheBuster { params["r"] = cacheBuster }

        return try await get("/recommendations", params: params)
    }

    // Visual search: query image -> Titan MM embed -> kNN over S3 Vectors.
    // Mirrors web fetchVisualSearch (POST /visual-search {imageBase64, ...}).
    // userId (or the anonymous id) makes the server keep the photo's embedding
    // as a graph photoseed; the response echoes it packed for on-device use.
    func fetchVisualSearch(
        imageBase64: String,
        text: String? = nil,
        limit: Int = 18,
        userId: String? = nil,
        intent: String? = nil,
        recipientRef: String? = nil
    ) async throws -> VectorResponse {
        var body: [String: Any] = ["imageBase64": imageBase64, "limit": limit]
        if let text, !text.isEmpty { body["text"] = text }
        body["userId"] = userId ?? InteractionQueue.anonymousUserId
        if let intent, !intent.isEmpty { body["intent"] = intent }
        if let recipientRef, !recipientRef.isEmpty { body["recipientRef"] = recipientRef }
        return try await post("/visual-search", body: body)
    }

    // Server-side swipe challenge (POST /challenges): resolves the seed
    // (captured image, catalog pin, or taste keys), builds the quality-filtered
    // banded deck in the Lambda, and returns the challengeId to share. Deck +
    // verdicts live entirely server-side from here.
    // deckMode "exact" (swipe lists): the guest deck is EXACTLY the seedKeys —
    // no lookalike padding, no hidden seed. `cards` carries client snapshots so
    // items outside the vector index still make the deck.
    func createChallenge(
        senderId: String,
        mode: String? = nil,
        seedImageBase64: String? = nil,
        seedPostId: String? = nil,
        seedKeys: [String]? = nil,
        seedText: String? = nil,
        inviterName: String? = nil,
        to: String? = nil,
        occasion: String? = nil,
        date: String? = nil,
        deckMode: String? = nil,
        cards: [[String: Any]]? = nil
    ) async throws -> ChallengeCreateResponse {
        let exact = deckMode == "exact"
        var seed: [String: Any] = [:]
        if let seedImageBase64 { seed["imageBase64"] = seedImageBase64 }
        if let seedPostId { seed["postId"] = seedPostId }
        if let seedKeys, !seedKeys.isEmpty { seed["seedKeys"] = Array(seedKeys.prefix(exact ? 40 : 8)) }
        if let seedText, !seedText.isEmpty { seed["text"] = seedText }

        var body: [String: Any] = ["senderId": senderId, "seed": seed]
        if let inviterName, !inviterName.isEmpty { body["inviterName"] = inviterName }
        if let to, !to.isEmpty { body["to"] = to }
        if let occasion, !occasion.isEmpty { body["occasion"] = occasion }
        if let date, !date.isEmpty { body["date"] = date }
        if let mode, !mode.isEmpty { body["mode"] = mode }
        if let deckMode, !deckMode.isEmpty { body["deckMode"] = deckMode }
        if let cards, !cards.isEmpty { body["cards"] = Array(cards.prefix(40)) }
        return try await post("/challenges", body: body)
    }

    // GET /challenges/{id} — the public view. For group gifts this carries the
    // shared tally (groupPicks + responders) every friend can see.
    func fetchChallengeStatus(challengeId: String) async throws -> ChallengeStatusResponse {
        try await get("/challenges/\(challengeId)")
    }

    // POST /challenges/{id}/response — submit swipes on a challenge deck (the
    // creator swiping their own group deck uses the same guest door friends do).
    // Passing anonId makes the server persist the swiper's OWN taste under that
    // id (claimed into their account at signup) — the recipient-entry warm start.
    func submitChallengeResponse(
        challengeId: String,
        guestName: String,
        swipes: [(id: String, dir: String)],
        anonId: String? = nil
    ) async throws {
        var guest: [String: Any] = ["name": guestName]
        if let anonId, !anonId.isEmpty { guest["anonId"] = anonId }
        let body: [String: Any] = [
            "guest": guest,
            "swipes": swipes.map { ["id": $0.id, "dir": $0.dir] },
        ]
        let _: ChallengeResponseAck = try await post("/challenges/\(challengeId)/response", body: body)
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
            var item: [String: Any] = [
                "userId": $0.userId,
                "targetId": $0.targetId,
                "type": $0.type,
                "createdAt": Int($0.queuedAt * 1000),
            ]
            // Per-event context ({mode:"gift", giftType, decisionMs, …}) so
            // gift-mode browsing can build per-recipient taste server-side.
            if let data = $0.data, !data.isEmpty { item["data"] = data }
            return item
        }
        let _: EmptyResponse = try await post("/interactions", body: ["items": items])
    }

    // MARK: - Connections (swipe-challenge responses; auth-gated server-side)

    // POST /connections/seen — clear the unseen flags (bell badge source).
    // Omitting connectionIds marks everything unseen as seen.
    func markConnectionsSeen(userId: String, connectionIds: [String]? = nil) async {
        var body: [String: Any] = ["userId": userId]
        if let connectionIds, !connectionIds.isEmpty { body["connectionIds"] = connectionIds }
        let _: EmptyResponse? = try? await post("/connections/seen", body: body)
    }

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

    // MARK: - Birthday freebies

    // Curated "free on your birthday" perks (see infra/src/birthday-freebies.mjs).
    func fetchBirthdayFreebies() async throws -> BirthdayPerksResponse {
        try await get("/birthday-freebies")
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

    private func delete<T: Decodable>(_ path: String, params: [String: String] = [:]) async throws -> T {
        var components = URLComponents(string: baseURL + path)!
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuth(&request)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        // Tolerate an empty body for 200/204 responses.
        if data.isEmpty, let empty = EmptyResponse() as? T { return empty }
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
            image: absoluteMediaURL(p?.image),
            images: p?.images?.map { absoluteMediaURL($0) ?? $0 }
        )

        return Post(
            id: api.postId,
            user: api.authorName ?? api.author ?? "reddit",
            ownerId: api.ownerId,
            authorImageUrl: absoluteMediaURL(api.authorImageUrl),
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
            feedEligible: api.feedEligible,
            giftType: api.giftType,
            serviceDuration: api.serviceDuration,
            contentType: api.contentType,
            mediaUrl: absoluteMediaURL(api.mediaUrl),
            posterUrl: absoluteMediaURL(api.posterUrl),
            story: api.story
        )
    }

    private func absoluteMediaURL(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value.hasPrefix("/") ? baseURL + value : value
    }

    private func normalizeUGCPost(_ post: UGCPost) -> UGCPost {
        var post = post
        post.authorImageUrl = absoluteMediaURL(post.authorImageUrl)
        post.mediaUrl = absoluteMediaURL(post.mediaUrl)
        post.posterUrl = absoluteMediaURL(post.posterUrl)
        return post
    }

    private func normalizePerson(_ value: PublicPerson) -> PublicPerson {
        var person = value
        person.imageUrl = absoluteMediaURL(person.imageUrl)
        person.giftShowcase = person.giftShowcase?.map { item in
            var item = item
            item.imageUrl = absoluteMediaURL(item.imageUrl)
            return item
        }
        person.posts = person.posts?.map(normalizeUGCPost)
        return person
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
