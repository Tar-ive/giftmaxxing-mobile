import Foundation

// Batched, offline-safe interaction uploader. Every like/save/impression used
// to be its own Lambda invocation (and the account has a hard concurrency cap
// of 10, per docs/backend-scaling-design.md). Events now land in the local
// taste profile instantly and are flushed to POST /interactions in batches —
// one invocation per ~N events instead of one per tap.

actor InteractionQueue {
    static let shared = InteractionQueue()

    struct PendingInteraction: Codable {
        let userId: String
        let targetId: String
        let type: String
        let queuedAt: Double
    }

    private var pending: [PendingInteraction] = []
    private var loaded = false
    private var flushTask: Task<Void, Never>?
    private var isFlushing = false

    private static let flushThreshold = 10
    private static let flushDelaySeconds: UInt64 = 20
    private static let queueCap = 500

    // Stable anonymous identity so server-side taste accrues pre-signup and
    // survives app restarts. A real signed-in user id takes precedence.
    static var anonymousUserId: String {
        let key = "gm.anonUserId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = "anon-" + UUID().uuidString.lowercased()
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    func enqueue(userId: String?, targetId: String, type: String) {
        loadIfNeeded()
        let uid = userId ?? Self.anonymousUserId
        pending.append(PendingInteraction(
            userId: uid,
            targetId: targetId,
            type: type,
            queuedAt: Date().timeIntervalSince1970
        ))
        if pending.count > Self.queueCap {
            pending.removeFirst(pending.count - Self.queueCap)
        }
        persist()

        if pending.count >= Self.flushThreshold {
            Task { await self.flush() }
        } else {
            scheduleDelayedFlush()
        }
    }

    // Called on app-background/foreground transitions and after threshold hits.
    func flush() async {
        loadIfNeeded()
        guard !isFlushing, !pending.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        let batch = Array(pending.prefix(100))
        do {
            try await APIClient.shared.sendInteractionsBatch(batch)
            pending.removeFirst(min(batch.count, pending.count))
            persist()
        } catch {
            // Keep events queued; next enqueue/foreground retries. Impressions
            // older than a day are dropped — stale view data isn't worth retries.
            let cutoff = Date().timeIntervalSince1970 - 86400
            pending.removeAll { $0.type == "impression" && $0.queuedAt < cutoff }
            persist()
        }
    }

    private func scheduleDelayedFlush() {
        guard flushTask == nil else { return }
        flushTask = Task {
            try? await Task.sleep(nanoseconds: Self.flushDelaySeconds * 1_000_000_000)
            flushTask = nil
            guard !Task.isCancelled else { return }
            await flush()
        }
    }

    // MARK: - Persistence (survives force-quit / offline)

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recommendation", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pending-interactions.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([PendingInteraction].self, from: data) {
            pending = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pending) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
