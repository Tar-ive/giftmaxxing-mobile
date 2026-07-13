import Foundation

// On-device user model. Every interaction (impression/like/save/hide/open) is
// folded into decayed aggregates locally, so personalization is instant, works
// offline, never requires a per-request DynamoDB interactions query, and the
// raw behavioral stream never has to leave the phone for ranking purposes.
//
// This replaces two pieces of per-request server work:
//   • userExcludeSet() — the seen/liked de-dup query the Lambda runs per page
//   • the interactions Query in GET /recommendations used to derive seeds

struct TasteEvent {
    enum Kind: String, Codable {
        case impression   // card scrolled into view
        case dwell        // lingered on a card (viewport dwell ≥ threshold)
        case open         // tapped through to product
        case like
        case unlike
        case save
        case unsave
        case hide         // explicit negative (left swipe / hide)
        case pledge       // put money into a pool for this item (gift-mode)
        case queueAdd     // added to the swipe list for a friend (gift-mode)
        case queueRemove

        var weight: Double {
            switch self {
            case .impression: return 0.03
            case .dwell: return 0.12
            case .open: return 0.7
            case .like: return 1.0
            case .unlike: return -1.0
            case .save: return 1.6
            case .unsave: return -1.6
            case .hide: return -1.2
            case .pledge: return 2.2
            case .queueAdd: return 0.8
            case .queueRemove: return -0.8
            }
        }

        // Only strong SELF signals seed vector similarity. Pledge/queueAdd are
        // gift-mode (chosen for someone else) — they inform vibes and the
        // product-vs-service split but must not steer the personal centroid
        // (research doc gap G2).
        var isSeedSignal: Bool { self == .like || self == .save || self == .open }

        // Explicit negatives feed the negative seed list (anti-centroid).
        var isNegativeSeedSignal: Bool { self == .hide || self == .unlike || self == .unsave }
    }

    let kind: Kind
    let postId: String
    let author: String
    let price: Double
    let vibes: [String]
    let category: String
    // "product" | "service" — drives giftTypeAffinity ("they'd rather get a
    // year of Spotify than a thing").
    var giftType: String = "product"
    // Scales the kind's base weight: an instant left-swipe (fast decision) is a
    // harder no than a hesitant one; a long dwell is a warmer impression.
    var weightScale: Double = 1
}

// Immutable snapshot handed to the ranker (safe to use off-actor).
struct TasteSnapshot: Sendable {
    var vibes: [String: Double] = [:]
    var totalVibeWeight: Double = 0
    var prefPrice: Double?
    var authorAffinity: [String: Double] = [:]
    var categoryAffinity: [String: Double] = [:]
    // "product" / "service" decayed engagement weights (may be negative).
    var giftTypeAffinity: [String: Double] = [:]
    var seen: Set<String> = []
    var seedKeys: [String] = []      // recent liked/saved/opened post ids, newest first
    var negSeedKeys: [String] = []   // recent hidden/unliked ids -> anti-centroid
    var topVibe: String? {
        vibes.max(by: { $0.value < $1.value })?.key
    }
}

actor TasteProfileStore {
    static let shared = TasteProfileStore()

    // Decayed aggregate state (persisted). Half-life keeps taste current without
    // storing the full event log.
    private struct State: Codable {
        var vibes: [String: Double] = [:]
        var authorAffinity: [String: Double] = [:]
        var categoryAffinity: [String: Double] = [:]
        // Decodes as [:] on stores written before the giftType split existed.
        var giftTypeAffinity: [String: Double]? = [:]
        var priceSum: Double = 0
        var priceWeight: Double = 0
        var seen: [String] = []          // insertion-ordered, capped
        var seedKeys: [String] = []      // newest first, capped
        var negSeedKeys: [String]? = []  // newest first, capped (optional: old stores)
        var lastDecayAt: Double = Date().timeIntervalSince1970
    }

    private var state = State()
    private var loaded = false
    private var saveTask: Task<Void, Never>?

    private static let halfLifeDays = 14.0
    private static let seenCap = 3000
    private static let seedCap = 24
    private static let negSeedCap = 24

    // MARK: - Recording

    func record(_ event: TasteEvent) {
        loadIfNeeded()
        applyDecay()

        let w = event.kind.weight * max(0.25, min(2, event.weightScale))
        if event.kind == .impression {
            markSeen(event.postId)
        } else {
            markSeen(event.postId)
            for v in event.vibes {
                state.vibes[v, default: 0] += w * 1.0
            }
            state.authorAffinity[event.author, default: 0] += w * 0.5
            state.categoryAffinity[event.category, default: 0] += w * 0.5
            // Product-vs-service preference: every engagement votes for the
            // gift type it happened on (dwell counts — lingering on service
            // cards is a soft "I'd take a membership").
            var gta = state.giftTypeAffinity ?? [:]
            gta[event.giftType == "service" ? "service" : "product", default: 0] += w * 0.6
            state.giftTypeAffinity = gta
            if w > 0, event.price > 0 {
                state.priceSum += event.price * w
                state.priceWeight += w
            }
        }

        if event.kind.isSeedSignal {
            state.seedKeys.removeAll { $0 == event.postId }
            state.seedKeys.insert(event.postId, at: 0)
            if state.seedKeys.count > Self.seedCap {
                state.seedKeys.removeLast(state.seedKeys.count - Self.seedCap)
            }
            var neg = state.negSeedKeys ?? []
            neg.removeAll { $0 == event.postId } // a fresh yes overrides an old no
            state.negSeedKeys = neg
        } else if event.kind.isNegativeSeedSignal {
            state.seedKeys.removeAll { $0 == event.postId }
            var neg = state.negSeedKeys ?? []
            neg.removeAll { $0 == event.postId }
            neg.insert(event.postId, at: 0)
            if neg.count > Self.negSeedCap {
                neg.removeLast(neg.count - Self.negSeedCap)
            }
            state.negSeedKeys = neg
        }

        scheduleSave()
    }

    // Fold a photo the user searched into taste as a seed key whose vector the
    // caller has already cached in VectorStore (visual search, gap G3).
    func addPhotoSeed(key: String) {
        loadIfNeeded()
        state.seedKeys.removeAll { $0 == key }
        state.seedKeys.insert(key, at: 0)
        if state.seedKeys.count > Self.seedCap {
            state.seedKeys.removeLast(state.seedKeys.count - Self.seedCap)
        }
        scheduleSave()
    }

    func snapshot() -> TasteSnapshot {
        loadIfNeeded()
        applyDecay()
        var snap = TasteSnapshot()
        snap.vibes = state.vibes
        snap.totalVibeWeight = state.vibes.values.filter { $0 > 0 }.reduce(0, +)
        snap.prefPrice = state.priceWeight > 0.5 ? state.priceSum / state.priceWeight : nil
        snap.authorAffinity = state.authorAffinity
        snap.categoryAffinity = state.categoryAffinity
        snap.giftTypeAffinity = state.giftTypeAffinity ?? [:]
        snap.seen = Set(state.seen)
        snap.seedKeys = state.seedKeys
        snap.negSeedKeys = state.negSeedKeys ?? []
        return snap
    }

    // MARK: - Internals

    private func markSeen(_ id: String) {
        guard !id.isEmpty else { return }
        state.seen.append(id)
        if state.seen.count > Self.seenCap {
            // Trim oldest third at once so we do it rarely.
            state.seen.removeFirst(Self.seenCap / 3)
        }
    }

    private func applyDecay() {
        let now = Date().timeIntervalSince1970
        let days = (now - state.lastDecayAt) / 86400
        guard days > 0.25 else { return }
        let factor = pow(0.5, days / Self.halfLifeDays)
        state.vibes = state.vibes.compactMapValues { abs($0 * factor) < 0.01 ? nil : $0 * factor }
        state.authorAffinity = state.authorAffinity.compactMapValues { abs($0 * factor) < 0.01 ? nil : $0 * factor }
        state.categoryAffinity = state.categoryAffinity.compactMapValues { abs($0 * factor) < 0.01 ? nil : $0 * factor }
        state.giftTypeAffinity = (state.giftTypeAffinity ?? [:]).compactMapValues { abs($0 * factor) < 0.01 ? nil : $0 * factor }
        state.priceSum *= factor
        state.priceWeight *= factor
        state.lastDecayAt = now
    }

    // MARK: - Persistence

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recommendation", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("taste-profile.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            state = decoded
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [state] in
            try? await Task.sleep(nanoseconds: 2_000_000_000) // debounce 2s
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(state) {
                try? data.write(to: Self.fileURL, options: .atomic)
            }
        }
    }
}
