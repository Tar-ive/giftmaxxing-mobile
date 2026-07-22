import Foundation
import Combine

/// Friends + DMs store — iOS port of web/lib/friends.ts.
/// Prefers the live AWS friends APIs; falls back to UserDefaults so the UI
/// works offline / before terraform apply creates the friends table.
@MainActor
final class FriendsStore: ObservableObject {
    static let shared = FriendsStore()

    @Published var friends: [Friendship] = []
    @Published var pending: [Friendship] = []
    @Published var discover: [PublicPerson] = []
    @Published var dms: [DmThread] = []
    @Published var isLoading = false

    private let api = APIClient.shared
    private static let friendsKey = "giftmaxxing_friends_v1"
    private static let dmsKey = "giftmaxxing_friend_dms_v1"
    private static let claimsKey = "giftmaxxing_circle_claims"

    private init() {}

    // MARK: - Refresh

    func refresh(userId: String?, query: String = "") async {
        isLoading = true
        defer { isLoading = false }

        // Keep this sequential on the main actor — `async let` closures are
        // nonisolated and can't call our MainActor-isolated local helpers.
        let people: [PublicPerson]
        if let items = try? await api.searchPeople(query: query, limit: 30), !items.isEmpty {
            people = items
        } else {
            people = Self.demoPeople(query: query, excluding: userId)
        }

        guard let userId, !userId.isEmpty else {
            discover = people.filter { $0.userId != "you" }
            friends = []
            pending = []
            dms = []
            return
        }

        let localAccepted = loadLocalFriends(userId: userId, status: "accepted")
        let localPending = loadLocalFriends(userId: userId, status: "pending")
        let remoteAccepted = try? await api.listFriends(userId: userId, status: "accepted")
        let remotePending = try? await api.listFriends(userId: userId, status: "pending")
        let accepted = merge(remote: remoteAccepted, local: localAccepted)
        let pend = merge(remote: remotePending, local: localPending)
        if remoteAccepted != nil || remotePending != nil {
            saveLocalFriends(userId: userId, edges: accepted + pend)
        }
        let threads = (try? await api.listDms(userId: userId))
            ?? loadLocalDms(userId: userId)

        discover = people.filter { $0.userId != userId }
        friends = accepted
        pending = pend
        dms = threads
    }

    // MARK: - Friendships

    func requestFriend(fromUserId: String, toUserId: String, circleId: String? = nil, toName: String? = nil, toHandle: String? = nil) async {
        if let _ = try? await api.requestFriend(fromUserId: fromUserId, toUserId: toUserId, circleId: circleId) {
            await refresh(userId: fromUserId)
            return
        }
        // Local fallback
        upsertLocalEdge(
            userId: fromUserId,
            otherId: toUserId,
            status: "pending",
            requestedBy: fromUserId,
            incoming: false,
            name: toName,
            handle: toHandle,
            circleId: circleId
        )
        upsertLocalEdge(
            userId: toUserId,
            otherId: fromUserId,
            status: "pending",
            requestedBy: fromUserId,
            incoming: true,
            name: AuthManager.shared.displayName,
            handle: nil,
            circleId: circleId
        )
        await refresh(userId: fromUserId)
    }

    func acceptFriend(userId: String, fromUserId: String) async {
        if let _ = try? await api.acceptFriend(userId: userId, fromUserId: fromUserId) {
            _ = try? await api.openDm(userId: userId, otherUserId: fromUserId)
            await refresh(userId: userId)
            return
        }
        upsertLocalEdge(
            userId: userId,
            otherId: fromUserId,
            status: "accepted",
            requestedBy: fromUserId,
            incoming: false,
            name: nil,
            handle: nil,
            circleId: nil
        )
        upsertLocalEdge(
            userId: fromUserId,
            otherId: userId,
            status: "accepted",
            requestedBy: fromUserId,
            incoming: false,
            name: nil,
            handle: nil,
            circleId: nil
        )
        _ = await openDm(userId: userId, otherUserId: fromUserId)
        await refresh(userId: userId)
    }

    func removeFriend(userId: String, friendId: String) async {
        _ = try? await api.removeFriend(userId: userId, friendId: friendId)
        removeLocalEdge(userId: userId, otherId: friendId)
        await refresh(userId: userId)
    }

    func status(userId: String, otherId: String) async -> String {
        if let res = try? await api.friendshipStatus(userId: userId, otherId: otherId) {
            if res.status == "pending", res.incoming == true { return "incoming" }
            return res.status
        }
        let edge = loadLocalFriends(userId: userId).first { $0.friendId == otherId }
        guard let edge else { return "none" }
        if edge.isPending, edge.incoming == true { return "incoming" }
        return edge.status
    }

    // MARK: - DMs

    @discardableResult
    func openDm(userId: String, otherUserId: String) async -> String? {
        if let tid = try? await api.openDm(userId: userId, otherUserId: otherUserId) {
            await refresh(userId: userId)
            return tid
        }
        let tid = Self.localThreadId(userId, otherUserId)
        var store = loadLocalDmStore()
        if store[tid] == nil {
            store[tid] = LocalDmThread(
                threadId: tid,
                userA: userId,
                userB: otherUserId,
                otherName: SocialUsers.name(for: otherUserId),
                messages: [],
                lastText: nil,
                lastAt: Date().timeIntervalSince1970 * 1000
            )
            saveLocalDmStore(store)
        }
        await refresh(userId: userId)
        return tid
    }

    func messages(for threadId: String) async -> [DmMessage] {
        do {
            let items = try await api.fetchDmMessages(threadId: threadId)
            return items
        } catch {
            return loadLocalDmStore()[threadId]?.messages ?? []
        }
    }

    @discardableResult
    func sendMessage(threadId: String, userId: String, name: String, text: String) async -> DmMessage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let msg = try? await api.sendDmMessage(threadId: threadId, userId: userId, name: name, text: trimmed) {
            await refresh(userId: userId)
            return msg
        }
        var store = loadLocalDmStore()
        guard var thread = store[threadId] else { return nil }
        let msg = DmMessage(
            id: "MSG#\(Int(Date().timeIntervalSince1970 * 1000))",
            userId: userId,
            name: name,
            text: String(trimmed.prefix(1000)),
            at: Date().timeIntervalSince1970 * 1000
        )
        thread.messages.append(msg)
        thread.lastText = String(msg.text.prefix(140))
        thread.lastAt = msg.at
        store[threadId] = thread
        saveLocalDmStore(store)
        await refresh(userId: userId)
        return msg
    }

    // MARK: - Circle claims

    func claimCircleSeat(circleId: String, userId: String, memberName: String) async -> Bool {
        if let _ = try? await api.claimCircleSeat(circleId: circleId, userId: userId, memberName: memberName) {
            return true
        }
        var map = loadClaims()
        var circle = map[circleId] ?? [:]
        circle[memberName.lowercased()] = userId
        map[circleId] = circle
        saveClaims(map)
        return true
    }

    func localClaim(circleId: String, memberName: String) -> String? {
        loadClaims()[circleId]?[memberName.lowercased()]
    }

    // MARK: - Local persistence

    private struct LocalEdgeStore: Codable {
        var edges: [String: [String: Friendship]] // userId → friendId → edge
    }

    private struct LocalDmThread: Codable {
        var threadId: String
        var userA: String
        var userB: String
        var otherName: String?
        var messages: [DmMessage]
        var lastText: String?
        var lastAt: Double
    }

    private func loadLocalFriends(userId: String, status: String? = nil) -> [Friendship] {
        loadLocalFriends(userId: userId).filter { status == nil || $0.status == status }
    }

    private func loadLocalFriends(userId: String) -> [Friendship] {
        guard let data = UserDefaults.standard.data(forKey: Self.friendsKey),
              let store = try? JSONDecoder().decode(LocalEdgeStore.self, from: data),
              let edges = store.edges[userId] else {
            return []
        }
        return Array(edges.values)
    }

    private func merge(remote: [Friendship]?, local: [Friendship]) -> [Friendship] {
        guard let remote else { return local }
        var merged = Dictionary(uniqueKeysWithValues: local.map { ($0.friendId, $0) })
        remote.forEach { merged[$0.friendId] = $0 }
        return merged.values.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
    }

    private func saveLocalFriends(userId: String, edges: [Friendship]) {
        var store = LocalEdgeStore(edges: [:])
        if let data = UserDefaults.standard.data(forKey: Self.friendsKey),
           let existing = try? JSONDecoder().decode(LocalEdgeStore.self, from: data) {
            store = existing
        }
        store.edges[userId] = Dictionary(uniqueKeysWithValues: edges.map { ($0.friendId, $0) })
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: Self.friendsKey)
        }
    }

    private func upsertLocalEdge(
        userId: String,
        otherId: String,
        status: String,
        requestedBy: String,
        incoming: Bool,
        name: String?,
        handle: String?,
        circleId: String?
    ) {
        var store = LocalEdgeStore(edges: [:])
        if let data = UserDefaults.standard.data(forKey: Self.friendsKey),
           let existing = try? JSONDecoder().decode(LocalEdgeStore.self, from: data) {
            store = existing
        }
        var userEdges = store.edges[userId] ?? [:]
        let prev = userEdges[otherId]
        userEdges[otherId] = Friendship(
            friendId: otherId,
            status: status,
            requestedBy: requestedBy,
            incoming: incoming,
            circleId: circleId ?? prev?.circleId,
            createdAt: prev?.createdAt ?? Date().timeIntervalSince1970 * 1000,
            updatedAt: Date().timeIntervalSince1970 * 1000,
            name: name ?? prev?.name,
            handle: handle ?? prev?.handle,
            bio: prev?.bio,
            interests: prev?.interests,
            imageUrl: prev?.imageUrl
        )
        store.edges[userId] = userEdges
        if let encoded = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(encoded, forKey: Self.friendsKey)
        }
    }

    private func removeLocalEdge(userId: String, otherId: String) {
        guard let data = UserDefaults.standard.data(forKey: Self.friendsKey),
              var store = try? JSONDecoder().decode(LocalEdgeStore.self, from: data) else { return }
        store.edges[userId]?[otherId] = nil
        store.edges[otherId]?[userId] = nil
        if let encoded = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(encoded, forKey: Self.friendsKey)
        }
    }

    private func loadLocalDmStore() -> [String: LocalDmThread] {
        guard let data = UserDefaults.standard.data(forKey: Self.dmsKey),
              let store = try? JSONDecoder().decode([String: LocalDmThread].self, from: data) else {
            return [:]
        }
        return store
    }

    private func saveLocalDmStore(_ store: [String: LocalDmThread]) {
        if let encoded = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(encoded, forKey: Self.dmsKey)
        }
    }

    private func loadLocalDms(userId: String) -> [DmThread] {
        loadLocalDmStore().values
            .filter { $0.userA == userId || $0.userB == userId }
            .map { t in
                let other = t.userA == userId ? t.userB : t.userA
                return DmThread(
                    threadId: t.threadId,
                    otherUserId: other,
                    otherName: t.otherName ?? SocialUsers.name(for: other),
                    otherHandle: nil,
                    lastText: t.lastText,
                    lastAt: t.lastAt
                )
            }
            .sorted { ($0.lastAt ?? 0) > ($1.lastAt ?? 0) }
    }

    private func loadClaims() -> [String: [String: String]] {
        guard let data = UserDefaults.standard.data(forKey: Self.claimsKey),
              let map = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            return [:]
        }
        return map
    }

    private func saveClaims(_ map: [String: [String: String]]) {
        if let encoded = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(encoded, forKey: Self.claimsKey)
        }
    }

    private static func localThreadId(_ a: String, _ b: String) -> String {
        let pair = [a, b].sorted()
        return "DM#\(pair[0])__\(pair[1])"
    }

    private static func demoPeople(query: String, excluding: String?) -> [PublicPerson] {
        let t = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return SocialUsers.all
            .filter { $0.key != "you" && $0.key != "maxi" && $0.key != excluding }
            .map { key, value in
                PublicPerson(
                    userId: key,
                    name: value.name,
                    handle: key,
                    bio: nil,
                    imageUrl: nil,
                    interests: nil,
                    materialisticCategories: nil,
                    style: nil,
                    role: nil,
                    visibility: "public"
                )
            }
            .filter {
                t.isEmpty
                    || $0.name.lowercased().contains(t)
                    || $0.handle.lowercased().contains(t)
            }
            .sorted { $0.name < $1.name }
    }
}
