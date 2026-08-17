import Foundation
import GiftmaxxingCore

// Batched, offline-safe interaction uploader. Every like/save/impression used
// to be its own Lambda invocation (and the account has a hard concurrency cap
// of 10, per docs/backend-scaling-design.md). Events now land in the local
// taste profile instantly and are flushed to POST /interactions in batches —
// one invocation per ~N events instead of one per tap.


public actor InteractionQueue {
    public static let shared = InteractionQueue()

    /// Set once at launch (see GiftmaxxingApp). Without it nothing uploads.
    private var uploader: InteractionUploading?

    /// The app injects its networking here at startup.
    public func setUploader(_ uploader: InteractionUploading) {
        self.uploader = uploader
    }

    /// Kept so `InteractionQueue.PendingInteraction` still resolves at every
    /// existing call site — the type itself lives in Core so both this module
    /// and Networking can see it without depending on each other.
    public typealias PendingInteraction = GiftmaxxingCore.PendingInteraction


    private var pending: [PendingInteraction] = []
    private var loaded = false
    private var flushTask: Task<Void, Never>?
    private var isFlushing = false

    private static let flushThreshold = 10
    private static let flushDelaySeconds: UInt64 = 20
    private static let queueCap = 500

    /// The identity itself lives in Core (`AnonymousIdentity`) so the API
    /// client can read it without importing this module. Kept here so the 14
    /// existing call sites don't churn.
    public static var anonymousUserId: String { AnonymousIdentity.current }

    public func enqueue(
        userId: String?, targetId: String, type: String, data: [String: String]? = nil,
        recommendationId: String? = nil, attributionToken: String? = nil,
        position: Int? = nil, dwellMs: Double? = nil, forceMixer: Bool = false
    ) {
        loadIfNeeded()
        let uid = userId ?? Self.anonymousUserId
        pending.append(PendingInteraction(
            userId: uid,
            targetId: targetId,
            type: type,
            queuedAt: Date().timeIntervalSince1970,
            data: data,
            recommendationId: recommendationId,
            attributionToken: attributionToken,
            position: position,
            dwellMs: dwellMs,
            forceMixer: forceMixer
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
    public func flush() async {
        loadIfNeeded()
        guard !isFlushing, !pending.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        let batch = Array(pending.prefix(100))
        do {
            let mixer = batch.filter { $0.recommendationId != nil || $0.forceMixer == true }
            let legacy = batch.filter { $0.recommendationId == nil && $0.forceMixer != true }
            guard let uploader else {
                assertionFailure("InteractionQueue has no uploader — every taste signal is being dropped. Wire it in GiftmaxxingApp.")
                return
            }
            if !legacy.isEmpty { try await uploader.sendInteractionsBatch(legacy) }
            if !mixer.isEmpty {
                try await uploader.submitMixerEvents(mixer.map { event in
                    var item: [String: Any] = [
                        "eventId": UUID().uuidString,
                        "type": event.type,
                        "itemId": event.targetId,
                        "timestamp": Int(event.queuedAt * 1000),
                        "recommendationId": event.recommendationId ?? "",
                    ]
                    if let token = event.attributionToken { item["attributionToken"] = token }
                    if let position = event.position { item["position"] = position }
                    if let dwellMs = event.dwellMs { item["dwellMs"] = dwellMs }
                    if let data = event.data { item["context"] = data }
                    return item
                }, anonymousId: mixer.first?.userId)
            }
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
