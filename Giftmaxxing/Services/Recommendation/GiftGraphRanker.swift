import Foundation
import GiftmaxxingCore
import GiftmaxxingRecommendation

// NOTE: this stayed in the app target when GiftmaxxingKit was extracted. It
// reads ThoughtfulnessStore, GiftingPrefs and Pool — all app-level state — so
// moving it would have dragged the whole store layer into the module. It is the
// next candidate once those are modularized.

// The knowledge-graph layer over the on-device ranker: a gift pick is a
// TRAVERSAL — user → recipient (relationship) → occasion (emotional weight) →
// their expressed interests + ground-truth feedback → candidate — not a plain
// collaborative filter. Every feature here is computed from data the app
// already holds locally (boards, pools, events, challenge responses, the
// Thoughtfulness ledger, cached Titan vectors); the server-side halves that
// can't be built from this repo (relationship-cohort social proof, a true
// multi-hop random walk over S3 Vectors) are specced in CLOUD.md §14.

// ── The user's gifting mindset (learned from their own behavior) ─────────────
// "Thoughtful planners" (letters, notes, weeks of runway) get intentionality-
// heavy ranking; "spontaneous fun-givers" (pools, quick saves) get speed and
// delight; last-minute users get express-friendly picks.
extension GiftMindset {
    @MainActor
    static func current() -> GiftMindset {
        let events = ThoughtfulnessStore.shared.events
        guard events.count >= 3 else {
            // Cold start: fall back to the onboarding persona.
            switch GiftingPrefs.persona {
            case "thoughtful": return .thoughtfulPlanner
            case "fast": return .lastMinuteHero
            case "special": return .spontaneousFunGiver
            default: return .balanced
            }
        }
        let deliberate = events.filter {
            $0.kind == .noteWritten || $0.kind == .letterWritten || $0.kind == .earlyPlanning
        }.count
        let spontaneous = events.filter {
            $0.kind == .poolStarted || $0.kind == .smallBusinessSave
        }.count
        if deliberate >= spontaneous * 2 { return .thoughtfulPlanner }
        if spontaneous >= deliberate * 2 { return .spontaneousFunGiver }
        return .balanced
    }
}


// ── Recipient context — the graph node the traversal starts from ─────────────
struct RecipientGraphContext {
    var recipientName: String?
    var relationship: String?      // partner | parent | sibling | best friend | colleague | friend
    var occasion: String?
    var emotionalWeight: Double    // 0.4 (just-because) … 1.0 (milestone)
    var interests: [String]        // expressed interests (challenge-response vibes)
    var feedbackSeedIds: [String]  // items they swiped YES on — ground truth
    var pastGiftCategories: Set<String> // gifted before → anti-repetition
    var daysToOccasion: Int?

    static let emotionalWeights: [String: Double] = [
        "wedding": 1.0, "graduation": 0.95, "anniversary": 0.9, "milestone": 1.0,
        "apology": 0.85, "birthday": 0.7, "baby-shower": 0.8, "housewarming": 0.6,
        "holiday": 0.55, "valentines": 0.75, "mothers-day": 0.75, "fathers-day": 0.75,
        "just-because": 0.4,
    ]

    // Assemble the context from what the device already knows about this
    // person: their board, every past shared board/pool (history), their
    // challenge responses (interests + ground truth), and the calendar.
    static func build(
        for board: SwipeList,
        allBoards: [SwipeList],
        pools: [Pool],
        connections: [SoftConnectionItem],
        events: [UpcomingEvent]
    ) -> RecipientGraphContext {
        let name = board.recipientName?.lowercased()

        // Expressed interests + yes-swipes from THIS recipient's responses.
        let theirConnections = connections.filter {
            name != nil && $0.guestName.lowercased() == name
        }
        let interests = Array(Set(theirConnections.flatMap { $0.vibes ?? [] }))
        let feedbackSeeds = Array(Set(theirConnections.flatMap { $0.seeds ?? [] }))

        // Past gift history for this person: categories on previously SHARED
        // boards and funded pools — repeating them shows no growth.
        var pastCategories = Set<String>()
        for other in allBoards where other.id != board.id
            && other.challengeId != nil
            && other.recipientName?.lowercased() == name {
            for post in other.posts {
                pastCategories.insert(TasteSignals.extract(from: post).category)
            }
        }
        for pool in pools where pool.forUser.lowercased() == name {
            if let product = pool.product {
                let post = Post(id: product.id, user: "pool", time: "", product: product, caption: "", likes: 0)
                pastCategories.insert(TasteSignals.extract(from: post).category)
            }
        }

        let nextEvent = events
            .filter { $0.recipientName?.lowercased() == name }
            .compactMap(\.daysUntil)
            .min()

        return RecipientGraphContext(
            recipientName: board.recipientName,
            relationship: board.relationship,
            occasion: board.occasion,
            emotionalWeight: emotionalWeights[board.occasion ?? ""] ?? 0.6,
            interests: interests,
            feedbackSeedIds: feedbackSeeds,
            pastGiftCategories: pastCategories,
            daysToOccasion: nextEvent
        )
    }
}

// ── The traversal ─────────────────────────────────────────────────────────────
enum GiftGraphRanker {

    private enum W {
        static let interests = 0.30
        static let feedback = 0.40      // recipient ground truth outranks everything
        static let relationship = 0.22
        static let repetition = -0.30   // gave this category before
        static let timeFit = 0.18
        static let socialProof = 0.10   // per-relationship cohort proof is server work (CLOUD.md §14)
    }

    // Relationship-appropriate categories (light, deterministic priors — the
    // vector/feedback terms do the fine work).
    private static let relationshipCategoryFit: [String: Set<String>] = [
        "partner": ["jewelry", "beauty", "experiences", "apparel", "home"],
        "parent": ["home", "kitchen", "food", "books"],
        "sibling": ["tech", "games", "apparel", "fitness"],
        "best friend": ["beauty", "stationery", "food", "games"],
        "colleague": ["stationery", "food", "books", "desk"],
        "friend": [],
    ]
    // Categories too intimate for a work relationship.
    private static let colleagueAvoid: Set<String> = ["jewelry", "apparel", "beauty"]

    private static let expressRetailers: Set<String> = [
        "amazon.com", "amzn.to", "a.co", "target.com", "walmart.com", "bestbuy.com",
    ]

    private static func isExpress(_ post: Post) -> Bool {
        let domain = (post.domain ?? "").lowercased().replacingOccurrences(of: "www.", with: "")
        return expressRetailers.contains(domain)
            || expressRetailers.contains(where: { domain.hasSuffix("." + $0) })
    }

    /// Re-score ranked candidates through the recipient's graph context.
    /// `feedbackSimilarities` = cosine of each candidate to the centroid of the
    /// items this recipient swiped YES on (computed by the caller from cached
    /// vectors) — the strongest edge in the graph.
    static func traverse(
        _ ranked: [RankedCandidate],
        context: RecipientGraphContext,
        mindset: GiftMindset,
        feedbackSimilarities: [String: Float] = [:]
    ) -> [RankedCandidate] {
        ranked.map { candidate in
            let post = candidate.post
            let signals = TasteSignals.extract(from: post)
            var delta = 0.0
            var reasons: [(Double, String)] = []

            // Expressed interests (Relationship Manager / challenge vibes).
            if !context.interests.isEmpty {
                let hits = signals.vibes.filter { context.interests.contains($0) }.count
                if hits > 0 {
                    let v = min(1, Double(hits) * 0.5) * W.interests
                    delta += v
                    reasons.append((v, "Matches \(context.recipientName ?? "their") interests"))
                }
            }

            // Ground truth: similar to what they actually swiped YES on.
            if let sim = feedbackSimilarities[post.id], sim > 0 {
                let v = Double(sim) * W.feedback * (0.6 + 0.4 * context.emotionalWeight)
                delta += v
                if sim > 0.5 {
                    reasons.append((v, "\(context.recipientName ?? "They") loved gifts like this"))
                }
            }

            // Relationship fit — priors scaled by the occasion's emotional weight.
            if let rel = context.relationship?.lowercased() {
                if let fit = relationshipCategoryFit[rel], fit.contains(signals.category) {
                    let v = W.relationship * context.emotionalWeight
                    delta += v
                    reasons.append((v, "A classic for a \(rel)"))
                }
                if rel == "colleague", colleagueAvoid.contains(signals.category) {
                    delta -= 0.35 // keep work gifts work-appropriate
                }
            }

            // Anti-repetition: gave this category to this person before.
            if context.pastGiftCategories.contains(signals.category) {
                delta += W.repetition
            }

            // Time to occasion: the scramble wants express-friendly retailers;
            // real runway earns deeper, more intentional picks.
            if let days = context.daysToOccasion {
                if days <= 5 {
                    delta += isExpress(post) ? W.timeFit : -0.12
                } else if days >= 14 {
                    delta += IntentionalityScore.score(for: post) * W.timeFit
                }
            }

            // Intentionality, weighted by who this giver is.
            delta += IntentionalityScore.score(for: post) * mindset.intentionalityWeight

            // Social proof (app-wide saves for now; per-relationship cohort
            // proof needs the server aggregation specced in CLOUD.md §14).
            delta += min(1, Double(post.likes) / 300) * W.socialProof

            let reason = reasons.max(by: { $0.0 < $1.0 })?.1 ?? candidate.reason
            return RankedCandidate(post: post, score: candidate.score + delta, reason: reason)
        }
        .sorted { $0.score > $1.score }
    }

    /// "Surprise me": a controlled walk AWAY from the predicted cluster.
    /// Instead of the closest matches, sample from the LOW-similarity band —
    /// quality-gated so exploration never means junk — with per-category
    /// de-dup so the surprises are actually diverse.
    static func surpriseWalk(
        _ candidates: [Post],
        centroidSimilarities: [String: Float],
        count: Int
    ) -> [Post] {
        let eligible = candidates.filter { $0.product.image != nil && $0.feedEligible != false }
        guard !eligible.isEmpty else { return [] }

        // Out-of-cluster = low (or unknown) similarity to the taste centroid.
        // Weight each by quality + intentionality + noise: random enough to
        // surprise, gated enough to stay good.
        var weighted: [(post: Post, weight: Double)] = eligible.map { post in
            let sim = Double(centroidSimilarities[post.id] ?? 0)
            let outOfCluster = max(0, 1 - sim * 1.6) // sim ≥ ~0.6 ≈ excluded
            let quality = post.qualityScore ?? 0.5
            let weight = outOfCluster * (0.4 + quality * 0.4 + IntentionalityScore.score(for: post) * 0.2)
                * Double.random(in: 0.6...1.4)
            return (post, weight)
        }
        weighted.sort { $0.weight > $1.weight }

        var picked: [Post] = []
        var usedCategories = Set<String>()
        for entry in weighted where picked.count < count {
            let category = TasteSignals.extract(from: entry.post).category
            // One repeat per category allowed; a third has to wait.
            if usedCategories.contains(category),
               picked.filter({ TasteSignals.extract(from: $0).category == category }).count >= 2 {
                continue
            }
            usedCategories.insert(category)
            picked.append(entry.post)
        }
        return picked.shuffled()
    }
}
