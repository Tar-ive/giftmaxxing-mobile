import Foundation
import UIKit
import os.signpost

// Behavioral analytics engine modeled after Instagram's impression tracking and
// Tinder's swipe telemetry. Uses Apple's os_signpost for precise interval
// measurement, NWPathMonitor-aware batching, and fire-and-forget upload to the
// /mobile/analytics endpoint.
//
// Key patterns implemented:
//   - Instagram: viewport-based dwell time, scroll velocity, feed depth, revisits
//   - Tinder: decision time per card, swipe velocity/direction, hesitation detection,
//     sequential pattern tracking (e.g. 5 rights in a row)
//   - Session lifecycle: foreground/background transitions, total active time
//   - Batch upload: events accumulate locally, flush every 30s or 50 events

@MainActor
final class AnalyticsEngine: ObservableObject {
    static let shared = AnalyticsEngine()

    private var eventBuffer: [AnalyticsEvent] = []
    private let bufferLimit = 50
    private let flushInterval: TimeInterval = 30

    private var sessionId: String = UUID().uuidString
    private var sessionStartTime: Date = Date()
    private var lastActiveTime: Date = Date()

    private var flushTimer: Timer?
    private let api = APIClient.shared

    // os_signpost for precise interval measurement (Apple's recommended approach)
    private let signpostLog = OSLog(subsystem: "com.giftmaxxing.ios", category: "Analytics")

    // Stable per-install identity for events that fire before sign-in (and to
    // stitch pre/post-signin behavior into one tester). Keychain-backed so it
    // survives reinstalls — TestFlight testers delete and re-add constantly.
    static let anonymousId: String = {
        let key = "analytics_anonymous_id"
        if let existing = KeychainStore.loadString(key: key) { return existing }
        let fresh = "anon_" + UUID().uuidString.lowercased()
        try? KeychainStore.saveString(key: key, value: fresh)
        return fresh
    }()

    private static let deviceModel: String = {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }()

    // Swipe pattern tracking (Tinder-style)
    private var consecutiveRights = 0
    private var consecutiveLefts = 0
    private var swipeStartTimes: [String: Date] = [:]

    // Feed tracking (Instagram-style)
    private var impressionTimestamps: [String: Date] = [:]
    private var seenPostIds: Set<String> = []
    private var maxScrollDepth: Int = 0
    private var scrollVelocitySamples: [Double] = []

    private init() {
        setupLifecycleObservers()
        startFlushTimer()
    }

    // MARK: - Session lifecycle

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleBecomeActive() }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleResignActive() }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleTerminate() }
        }
    }

    private func handleBecomeActive() {
        let wasBackgrounded = lastActiveTime.timeIntervalSinceNow < -1
        let backgroundDurationMs = -lastActiveTime.timeIntervalSinceNow * 1000
        lastActiveTime = Date()

        if wasBackgrounded {
            track(.sessionResume, properties: [
                "sessionId": .string(sessionId),
                "backgroundDurationMs": .double(backgroundDurationMs),
            ])
        }
    }

    private func handleResignActive() {
        let activeDuration = Date().timeIntervalSince(lastActiveTime)
        track(.sessionBackground, properties: [
            "sessionId": .string(sessionId),
            "activeDurationMs": .double(activeDuration * 1000),
        ])
        flush()
    }

    private func handleTerminate() {
        let totalDuration = Date().timeIntervalSince(sessionStartTime)
        track(.sessionEnd, properties: [
            "sessionId": .string(sessionId),
            "totalDurationMs": .double(totalDuration * 1000),
            "maxScrollDepth": .int(maxScrollDepth),
            "totalEvents": .int(eventBuffer.count),
        ])
        flushSync()
    }

    func startSession() {
        sessionId = UUID().uuidString
        sessionStartTime = Date()
        lastActiveTime = Date()
        consecutiveRights = 0
        consecutiveLefts = 0
        seenPostIds.removeAll()
        maxScrollDepth = 0

        track(.sessionStart, properties: [
            "sessionId": .string(sessionId),
            "thermalState": .string(thermalStateString()),
        ])
    }

    // MARK: - Feed tracking (Instagram-style)

    // Called when a post enters the visible viewport (onAppear)
    func trackImpression(postId: String, position: Int, source: String = "feed") {
        let isRevisit = seenPostIds.contains(postId)
        seenPostIds.insert(postId)
        impressionTimestamps[postId] = Date()
        maxScrollDepth = max(maxScrollDepth, position)

        os_signpost(.begin, log: signpostLog, name: "PostDwell", "%{public}s", postId)

        if isRevisit {
            track(.feedRevisit, properties: [
                "postId": .string(postId),
                "position": .int(position),
                "source": .string(source),
            ])
        } else {
            track(.feedImpression, properties: [
                "postId": .string(postId),
                "position": .int(position),
                "source": .string(source),
                "sessionId": .string(sessionId),
            ])
        }
    }

    // Called when a post leaves the visible viewport (onDisappear)
    func trackImpressionEnd(postId: String, position: Int) {
        os_signpost(.end, log: signpostLog, name: "PostDwell", "%{public}s", postId)

        guard let startTime = impressionTimestamps.removeValue(forKey: postId) else { return }
        let dwellMs = Date().timeIntervalSince(startTime) * 1000

        // Only track meaningful dwell (>200ms filters out fast scrolls)
        guard dwellMs > 200 else { return }

        track(.feedDwell, properties: [
            "postId": .string(postId),
            "position": .int(position),
            "dwellMs": .double(dwellMs),
            // Instagram bins: glance (<1s), scan (1-3s), read (3-10s), study (>10s)
            "dwellBucket": .string(dwellBucket(ms: dwellMs)),
        ])
    }

    // Called on scroll events to track velocity (Instagram tracks this to detect
    // "mindless scrolling" vs. "intentional browsing")
    func trackScrollVelocity(velocity: Double, currentPosition: Int) {
        scrollVelocitySamples.append(abs(velocity))

        // Emit scroll depth event every 10 posts
        if currentPosition > 0 && currentPosition % 10 == 0 {
            let avgVelocity = scrollVelocitySamples.reduce(0, +) / Double(max(1, scrollVelocitySamples.count))
            track(.feedScrollDepth, properties: [
                "depth": .int(currentPosition),
                "avgScrollVelocity": .double(avgVelocity),
                "sessionId": .string(sessionId),
            ])
            scrollVelocitySamples.removeAll()
        }
    }

    // MARK: - Swipe tracking (Tinder-style)

    // Called when a new card is shown in the swipe deck
    func trackCardShown(postId: String, position: Int, totalCards: Int) {
        swipeStartTimes[postId] = Date()
        os_signpost(.begin, log: signpostLog, name: "SwipeDecision", "%{public}s", postId)

        track(.swipeCardShown, properties: [
            "postId": .string(postId),
            "position": .int(position),
            "totalCards": .int(totalCards),
            "sessionId": .string(sessionId),
        ])
    }

    // Called on swipe right (like) — captures Tinder-style decision metrics
    func trackSwipeRight(postId: String, velocity: Double, position: Int) {
        os_signpost(.end, log: signpostLog, name: "SwipeDecision", "%{public}s", postId)

        let decisionMs = decisionTime(for: postId)
        consecutiveRights += 1
        consecutiveLefts = 0

        track(.swipeRight, properties: [
            "postId": .string(postId),
            "position": .int(position),
            "decisionTimeMs": .double(decisionMs),
            // Tinder classifies: snap (<500ms), quick (500ms-2s), considered (2-5s), studied (>5s)
            "decisionBucket": .string(decisionBucket(ms: decisionMs)),
            "swipeVelocity": .double(velocity),
            "consecutiveRights": .int(consecutiveRights),
            "sessionId": .string(sessionId),
        ])

        // Tinder detects "spam swiping" (>10 consecutive rights at <500ms each)
        if consecutiveRights >= 10 && decisionMs < 500 {
            track(.swipeHesitation, properties: [
                "type": .string("spam_right_detected"),
                "count": .int(consecutiveRights),
            ])
        }
    }

    // Called on swipe left (skip)
    func trackSwipeLeft(postId: String, velocity: Double, position: Int) {
        os_signpost(.end, log: signpostLog, name: "SwipeDecision", "%{public}s", postId)

        let decisionMs = decisionTime(for: postId)
        consecutiveLefts += 1
        consecutiveRights = 0

        track(.swipeLeft, properties: [
            "postId": .string(postId),
            "position": .int(position),
            "decisionTimeMs": .double(decisionMs),
            "decisionBucket": .string(decisionBucket(ms: decisionMs)),
            "swipeVelocity": .double(velocity),
            "consecutiveLefts": .int(consecutiveLefts),
            "sessionId": .string(sessionId),
        ])
    }

    // Detect hesitation: user starts dragging but releases without swiping
    func trackSwipeHesitation(postId: String, dragDistance: Double, dragDurationMs: Double) {
        track(.swipeHesitation, properties: [
            "postId": .string(postId),
            "type": .string("drag_cancel"),
            "dragDistance": .double(dragDistance),
            "dragDurationMs": .double(dragDurationMs),
        ])
    }

    func trackDeckComplete(yesCount: Int, noCount: Int, totalCards: Int) {
        let totalDecisionTime = Date().timeIntervalSince(sessionStartTime) * 1000

        track(.swipeDeckComplete, properties: [
            "yesCount": .int(yesCount),
            "noCount": .int(noCount),
            "totalCards": .int(totalCards),
            "yesRate": .double(Double(yesCount) / Double(max(1, yesCount + noCount))),
            "avgDecisionTimeMs": .double(totalDecisionTime / Double(max(1, totalCards))),
            "sessionId": .string(sessionId),
        ])
    }

    // A swipe list the recipient opened but didn't finish — how far they got
    // is itself signal (and distinguishes "not interested" from "never saw it").
    func trackChallengeAbandoned(challengeId: String, swiped: Int, deckSize: Int, yesCount: Int) {
        track(.challengeAbandoned, properties: [
            "challengeId": .string(challengeId),
            "swiped": .int(swiped),
            "deckSize": .int(deckSize),
            "yesCount": .int(yesCount),
            "completionRate": .double(Double(swiped) / Double(max(1, deckSize))),
            "sessionId": .string(sessionId),
        ])
    }

    // MARK: - Content interactions

    func trackContentAction(_ action: AnalyticsEvent.EventType, postId: String, source: String = "feed") {
        let dwellMs: Double
        if let start = impressionTimestamps[postId] {
            dwellMs = Date().timeIntervalSince(start) * 1000
        } else {
            dwellMs = 0
        }

        track(action, properties: [
            "postId": .string(postId),
            "source": .string(source),
            "dwellBeforeActionMs": .double(dwellMs),
            "sessionId": .string(sessionId),
        ])
    }

    // MARK: - Navigation

    func trackTabSwitch(from: String, to: String) {
        track(.tabSwitch, properties: [
            "fromTab": .string(from),
            "toTab": .string(to),
            "sessionId": .string(sessionId),
        ])
    }

    func trackScreenView(screen: String) {
        track(.screenView, properties: [
            "screen": .string(screen),
            "sessionId": .string(sessionId),
        ])
    }

    // MARK: - Product funnel

    func trackAffiliateClick(postId: String, productUrl: String, source: String, destination: String? = nil) {
        var properties: [String: AnyCodableValue] = [
            "postId": .string(postId),
            "productUrl": .string(productUrl),
            "source": .string(source),
            "sessionId": .string(sessionId),
        ]
        // Where the click actually landed: "amazon_app" (universal link into the
        // Amazon app) vs "in_app_browser" — measures the app-open rate.
        if let destination {
            properties["destination"] = .string(destination)
        }
        track(.productAffiliateClick, properties: properties)
    }

    // MARK: - Search

    func trackSearch(query: String, resultCount: Int) {
        track(.searchQuery, properties: [
            "query": .string(query),
            "resultCount": .int(resultCount),
            "sessionId": .string(sessionId),
        ])
    }

    // MARK: - Maxi AI

    func trackMaxiMessage(conversationLength: Int) {
        track(.maxiMessageSent, properties: [
            "conversationLength": .int(conversationLength),
            "sessionId": .string(sessionId),
        ])
    }

    // MARK: - Core

    private func track(_ type: AnalyticsEvent.EventType, properties: [String: AnyCodableValue] = [:]) {
        var enriched = properties
        enriched["platform"] = .string("ios")
        enriched["appVersion"] = .string(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
        enriched["buildNumber"] = .string(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0")
        enriched["deviceModel"] = .string(Self.deviceModel)
        enriched["osVersion"] = .string(UIDevice.current.systemVersion)
        // userId = account when signed in, anonymous id otherwise; anonymousId
        // rides along always so one tester's whole history stitches together.
        enriched["anonymousId"] = .string(Self.anonymousId)
        enriched["userId"] = .string(AuthManager.shared.userId ?? Self.anonymousId)

        let event = AnalyticsEvent(type: type, properties: enriched)
        eventBuffer.append(event)

        if eventBuffer.count >= bufferLimit {
            flush()
        }
    }

    // MARK: - Flush

    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }

    func flush() {
        guard !eventBuffer.isEmpty else { return }
        let batch = eventBuffer
        eventBuffer.removeAll()

        Task {
            await uploadBatch(batch)
        }
    }

    private func flushSync() {
        guard !eventBuffer.isEmpty else { return }
        let batch = eventBuffer
        eventBuffer.removeAll()

        // Best-effort synchronous flush on app termination — encode and persist
        // to UserDefaults for retry on next launch
        if let data = try? JSONEncoder().encode(batch) {
            UserDefaults.standard.set(data, forKey: "pendingAnalytics")
        }
    }

    func retryPendingAnalytics() {
        guard let data = UserDefaults.standard.data(forKey: "pendingAnalytics"),
              let events = try? JSONDecoder().decode([AnalyticsEvent].self, from: data) else {
            return
        }
        UserDefaults.standard.removeObject(forKey: "pendingAnalytics")

        Task {
            await uploadBatch(events)
        }
    }

    private var consecutiveFailures = 0
    private var nextRetryTime: Date?

    private func uploadBatch(_ events: [AnalyticsEvent]) async {
        guard !events.isEmpty else { return }

        // Exponential backoff: skip if we're in a cooldown period after repeated failures
        if let nextRetry = nextRetryTime, Date() < nextRetry {
            let requeued = Array(events.prefix(200))
            eventBuffer.insert(contentsOf: requeued, at: 0)
            return
        }

        do {
            let payload = events.map { event -> [String: Any] in
                var dict: [String: Any] = [
                    "eventId": event.id,
                    "type": event.type.rawValue,
                    "timestamp": event.timestamp,
                ]
                for (key, value) in event.properties {
                    switch value {
                    case .string(let v): dict[key] = v
                    case .int(let v): dict[key] = v
                    case .double(let v): dict[key] = v
                    case .bool(let v): dict[key] = v
                    }
                }
                return dict
            }

            try await api.uploadAnalytics(events: payload)
            consecutiveFailures = 0
            nextRetryTime = nil
        } catch {
            consecutiveFailures += 1
            // Exponential backoff: 30s, 60s, 120s, 240s, capped at 5 min
            let backoffSeconds = min(300, 30 * pow(2.0, Double(consecutiveFailures - 1)))
            nextRetryTime = Date().addingTimeInterval(backoffSeconds)

            // Re-buffer failed events (max 200 to prevent unbounded growth)
            let requeued = Array(events.prefix(200))
            eventBuffer.insert(contentsOf: requeued, at: 0)
        }
    }

    // MARK: - Helpers

    private func decisionTime(for postId: String) -> Double {
        guard let start = swipeStartTimes.removeValue(forKey: postId) else { return 0 }
        return Date().timeIntervalSince(start) * 1000
    }

    private func dwellBucket(ms: Double) -> String {
        switch ms {
        case ..<1000: return "glance"
        case 1000..<3000: return "scan"
        case 3000..<10000: return "read"
        default: return "study"
        }
    }

    private func decisionBucket(ms: Double) -> String {
        switch ms {
        case ..<500: return "snap"
        case 500..<2000: return "quick"
        case 2000..<5000: return "considered"
        default: return "studied"
        }
    }

    private func thermalStateString() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
