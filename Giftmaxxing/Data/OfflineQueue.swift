import Foundation
import SwiftData
import Network

@MainActor
final class OfflineQueue: ObservableObject {
    static let shared = OfflineQueue()

    @Published var isOnline = true
    @Published var pendingCount = 0

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.giftmaxxing.networkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                if path.status == .satisfied {
                    self?.flushWhenReady()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func enqueue(context: ModelContext, method: String, path: String, body: [String: Any]? = nil) {
        let action = PendingAction(method: method, path: path, body: body)
        context.insert(action)
        try? context.save()
        pendingCount += 1

        if isOnline {
            flushWhenReady()
        }
    }

    func recordInteraction(context: ModelContext, userId: String, targetId: String, type: String) {
        let interaction = CachedInteraction(userId: userId, targetId: targetId, type: type)
        context.insert(interaction)
        try? context.save()

        if isOnline {
            Task {
                await APIClient.shared.recordInteraction(
                    userId: userId.isEmpty ? nil : userId,
                    targetId: targetId,
                    type: type
                )
                interaction.synced = true
                try? context.save()
            }
        }
    }

    private func flushWhenReady() {
        Task {
            await SyncEngine.shared.flushOfflineQueue(
                context: DataController.shared.mainContext
            )
            // updatePendingCount is synchronous (SwiftData fetchCount on MainActor).
            updatePendingCount()
        }
    }

    private func updatePendingCount() {
        let descriptor = FetchDescriptor<PendingAction>()
        if let count = try? DataController.shared.mainContext.fetchCount(descriptor) {
            pendingCount = count
        }
    }
}
