import Foundation
import SwiftData
import SwiftUI

@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?

    private let api = APIClient.shared
    private let lastSyncKey = "lastSyncTimestamp"

    private init() {
        if let ts = UserDefaults.standard.object(forKey: lastSyncKey) as? Double {
            lastSyncDate = Date(timeIntervalSince1970: ts)
        }
    }

    func syncFeed(context: ModelContext, force: Bool = false) async {
        guard !isSyncing else { return }
        isSyncing = true

        do {
            let page = try await api.fetchFeed(limit: 40)
            let descriptor = FetchDescriptor<CachedPost>(
                sortBy: [SortDescriptor(\.feedPosition)]
            )
            let existing = try context.fetch(descriptor)

            let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.postId, $0) })

            for (index, post) in page.posts.enumerated() {
                if let cached = existingById[post.id] {
                    cached.likes = post.likes
                    cached.commentCount = post.displayCommentCount
                    cached.feedPosition = index
                    cached.cachedAt = Date()
                } else {
                    let cached = CachedPost(from: post, position: index)
                    context.insert(cached)
                }
            }

            try context.save()
            lastSyncDate = Date()
            UserDefaults.standard.set(lastSyncDate!.timeIntervalSince1970, forKey: lastSyncKey)
        } catch {
            // sync failure is non-fatal; UI shows cached data
        }

        isSyncing = false
    }

    func syncInteractions(context: ModelContext) async {
        let descriptor = FetchDescriptor<CachedInteraction>(
            predicate: #Predicate { !$0.synced }
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        for interaction in pending {
            await api.recordInteraction(
                userId: interaction.userId.isEmpty ? nil : interaction.userId,
                targetId: interaction.targetId,
                type: interaction.type
            )
            interaction.synced = true
        }

        try? context.save()
    }

    func syncEvents(context: ModelContext, userId: String) async {
        do {
            let events = try await api.fetchUpcomingEvents(userId: userId)
            let descriptor = FetchDescriptor<CachedEvent>()
            let existing = try context.fetch(descriptor)
            let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.eventId, $0) })

            for event in events {
                if existingById[event.id] == nil {
                    let gift = GiftEvent(
                        id: event.id,
                        type: event.type ?? "birthday",
                        title: event.title ?? event.recipientName ?? "Event",
                        date: Date(timeIntervalSince1970: (event.date ?? 0) / 1000),
                        recipientName: event.recipientName ?? event.recipient?.name ?? "",
                        scope: event.scope
                    )
                    let cached = CachedEvent(from: gift, userId: userId)
                    context.insert(cached)
                }
            }

            try context.save()
        } catch {
            // non-fatal
        }
    }

    func flushOfflineQueue(context: ModelContext) async {
        let descriptor = FetchDescriptor<PendingAction>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        guard let actions = try? context.fetch(descriptor), !actions.isEmpty else { return }

        for action in actions {
            do {
                try await api.executeRaw(
                    method: action.method,
                    path: action.path,
                    body: action.bodyDictionary
                )
                context.delete(action)
            } catch {
                action.retryCount += 1
                if !action.canRetry {
                    context.delete(action)
                }
            }
        }

        try? context.save()
    }

    func performFullSync(context: ModelContext, userId: String?) async {
        isSyncing = true

        await syncFeed(context: context)
        await syncInteractions(context: context)
        await flushOfflineQueue(context: context)

        if let userId {
            await syncEvents(context: context, userId: userId)
        }

        isSyncing = false
    }
}
