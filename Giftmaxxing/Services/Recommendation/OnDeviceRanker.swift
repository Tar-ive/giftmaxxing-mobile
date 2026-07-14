import Foundation

// The on-device final-stage ranker. Instagram-style layered serving, mapped to
// this app:
//
//   Layer 1  retrieval          server   byFeed GSI window / S3 Vectors kNN
//   Layer 2  integrity gate     device   seen de-dup + ContentQuality (was per-request Lambda work)
//   Layer 3  cheap features     device   quality, social proof, recency, facet match (parity with scorePost)
//   Layer 4  personalization    device   taste vibes, price fit, author affinity, vector cosine to taste centroid
//   Layer 5  session re-rank    device   diversity spacing + exploration
//
// The server keeps doing what only it can (full-corpus retrieval); everything
// per-user moves here. That lets the client request GENERIC candidate pages
// (no userId → CloudFront-cacheable → most pages never invoke Lambda) while
// personalization quality goes UP, because local signals are richer and
// fresher than what the server ever saw.

struct RankedCandidate {
    let post: Post
    let score: Double
    let reason: String?
}

struct RankingContext {
    var budget: Double?
    var eventBoost: Double = 0
    var recipient: String?
    var occasion: String?
    // Consult-declared interests ("world vibes") — the cold-start taste signal
    // for brand-new users whose profile has zero interactions yet.
    var consultVibes: [String] = []
    // Who this giver is (learned from their Thoughtfulness ledger) — scales
    // how hard the gift-graph intentionality feature pulls.
    var mindset: GiftMindset = .balanced
    var now: Date = Date()
}

enum OnDeviceRanker {

    // Scoring weights. Layer-3 terms mirror infra/src/handler.mjs scorePost()
    // so device and server ranking stay consistent; layer-4 terms are the
    // device-only personalization the server used to approximate.
    private enum W {
        static let social = 0.35
        static let tasteFacet = 0.25
        static let recency = 0.10
        static let quality = 0.40
        static let recipient = 0.20
        static let occasion = 0.15
        static let budgetFit = 0.15
        static let tasteVibes = 0.45
        static let priceFit = 0.15
        static let author = 0.20
        static let vector = 0.35
        static let vectorNeg = 0.25   // similarity to the HIDDEN-items centroid
        static let giftTypeLean = 0.12 // product-vs-service preference
        static let gallery = 0.22      // multi-image product carousels (Shopify/Etsy)
        static let explore = 0.11
    }

    static func rank(
        candidates: [Post],
        profile: TasteSnapshot,
        centroid: [Float]? = nil,
        vectorSimilarities: [String: Float] = [:],
        negSimilarities: [String: Float] = [:],
        context: RankingContext = RankingContext()
    ) -> [RankedCandidate] {

        // ── Layer 2: integrity ──────────────────────────────────────────────
        var seenIds = Set<String>()
        let eligible = candidates.filter { post in
            guard !post.id.isEmpty, !seenIds.contains(post.id), !profile.seen.contains(post.id) else { return false }
            seenIds.insert(post.id)
            // The server's flag is a veto, not a pass: the on-device rules can
            // be NEWER than the deployed Lambda (e.g. the non-gift merchandise
            // gate), so a server "eligible" still has to clear the local
            // classifier — that's how a filter fix reaches users app-side
            // before the backend redeploys.
            if post.feedEligible == false { return false }
            // Curated services are hand-picked (their domains — youtube.com
            // for a Premium year — misfire every text heuristic); trust ingest.
            if post.isService { return post.feedEligible ?? true }
            let q = ContentQuality.classify(
                title: post.caption.isEmpty ? post.product.name : post.caption,
                domain: post.domain,
                link: post.productUrl ?? post.url,
                price: post.product.price
            )
            return q.feedEligible
        }

        // ── Layers 3+4: per-candidate scoring ───────────────────────────────
        var scored: [(RankedCandidate, signals: TasteSignals.ItemSignals)] = []
        scored.reserveCapacity(eligible.count)

        for post in eligible {
            let signals = TasteSignals.extract(from: post)
            var s = 0.0
            var reasons: [(weightedValue: Double, text: String)] = []

            // Layer 3 — cheap features (scorePost parity).
            s += min(1, Double(post.likes) / 500) * W.social
            let quality = post.qualityScore ?? ContentQuality.classify(
                title: post.caption.isEmpty ? post.product.name : post.caption,
                domain: post.domain,
                link: post.productUrl ?? post.url,
                price: post.product.price
            ).qualityScore
            s += quality * W.quality

            let occMult = 1 + max(0, min(1, context.eventBoost))
            // Recipient fit: the catalog's recipient tag when set, otherwise the
            // text-inferred audience (most pins are untagged — without inference
            // a "for him" feed still read overwhelmingly feminine). Clear
            // opposites sink hard; neutral/unisex items ride on other signals.
            if let r = context.recipient, r == "men" || r == "women" {
                let inferred = AudienceClassifier.infer(for: post)
                if post.recipient == r || inferred == r {
                    s += W.recipient * occMult
                    reasons.append((W.recipient * occMult, "Great for \(r == "men" ? "him" : "her")"))
                } else if (post.recipient == "men" || post.recipient == "women") && post.recipient != r {
                    s -= 0.3
                } else if inferred != nil {
                    s -= 0.3
                }
            } else if let r = context.recipient, r != "anyone", post.recipient == r {
                s += W.recipient * occMult
                reasons.append((W.recipient * occMult, "Great for your \(r)"))
            }
            if let o = context.occasion, o != "any", post.occasion == o {
                s += W.occasion * occMult
            }
            if let budget = context.budget, post.product.price > 0 {
                let price = post.product.price
                let fit = price <= budget
                    ? W.budgetFit
                    : max(-0.1, W.budgetFit - ((price - budget) / budget) * 0.25)
                s += fit
                if fit > 0.1 { reasons.append((fit, "Fits your budget")) }
            }

            // Layer 4 — personalization from the local taste profile.
            var tasteMatch = 0.5 // neutral cold start (parity with web ranker)
            if profile.totalVibeWeight > 0 {
                let raw = signals.vibes.reduce(0.0) { $0 + max(0, profile.vibes[$1] ?? 0) }
                tasteMatch = min(1, raw / (profile.totalVibeWeight * 0.6))
                // Negative vibe feedback pulls below neutral.
                let neg = signals.vibes.reduce(0.0) { $0 + min(0, profile.vibes[$1] ?? 0) }
                tasteMatch = max(0, tasteMatch + neg * 0.1)
            } else if !context.consultVibes.isEmpty {
                // Zero interactions yet — target by the consult's declared
                // interests instead of treating every card as equally neutral.
                let hits = signals.vibes.filter { context.consultVibes.contains($0) }.count
                tasteMatch = min(1, 0.35 + Double(hits) * 0.3)
                if hits > 0, let hit = signals.vibes.first(where: { context.consultVibes.contains($0) }) {
                    reasons.append((tasteMatch * W.tasteVibes, "You said you're into \(hit)"))
                }
            }
            s += tasteMatch * W.tasteVibes
            if profile.totalVibeWeight > 0, tasteMatch > 0.6,
               let top = signals.vibes.first(where: { (profile.vibes[$0] ?? 0) > 0 }) {
                reasons.append((tasteMatch * W.tasteVibes, "Matches your \(top) taste"))
            }

            // Photos are the product: an imageless PRODUCT card (catalog rows
            // awaiting enrichment) shouldn't outrank a real photo at equal
            // score. Services are exempt — their designed card is intentional.
            if post.product.image == nil, !post.isService {
                s -= 0.12
            }

            if let pref = profile.prefPrice, post.product.price > 0 {
                let spread = max(25, pref * 0.6)
                let z = (post.product.price - pref) / spread
                s += exp(-(z * z)) * W.priceFit
            }

            let authorScore = min(1, max(-1, profile.authorAffinity[post.user] ?? 0))
            s += authorScore * W.author
            if authorScore > 0.5 {
                reasons.append((authorScore * W.author, "From \(post.user), whose finds you like"))
            }
            if let catScore = profile.categoryAffinity[signals.category], catScore < -0.5 {
                s -= 0.15 // user consistently hides this category
            }

            // Vector affinity: cosine of this item to the taste centroid in the
            // SAME Titan space the server index uses (vectors cached on device).
            if let sim = vectorSimilarities[post.id] {
                let v = Double(max(0, sim))
                s += v * W.vector
                if v > 0.55 { reasons.append((v * W.vector, "Similar to gifts you saved")) }
            }
            // Anti-centroid: similarity to what the user explicitly HID sinks
            // the card — left-swipes never leave the device, but they rank here.
            if let negSim = negSimilarities[post.id] {
                s -= Double(max(0, negSim)) * W.vectorNeg
            }

            // Product-vs-service lean ("they'd rather get a year of Spotify
            // than a thing") once there's enough signal to trust the split.
            let productW = profile.giftTypeAffinity["product"] ?? 0
            let serviceW = profile.giftTypeAffinity["service"] ?? 0
            let leanDenom = abs(productW) + abs(serviceW)
            if leanDenom > 1 {
                let own = post.isService ? serviceW : productW
                let other = post.isService ? productW : serviceW
                let lean = max(-1, min(1, (own - other) / leanDenom))
                s += lean * W.giftTypeLean
                if post.isService, lean > 0.4 {
                    reasons.append((lean * W.giftTypeLean, "You lean toward gift-able services"))
                }
            }

            // Multi-image carousels (Shopify/Etsy product galleries) are the
            // richest cards — swipeable, real listings. Float them above the
            // single static Pinterest photos that otherwise dominate the feed.
            if post.product.gallery.count > 1 {
                s += W.gallery
            }

            // Gift-graph layer: intentionality (story, maker origin, committed
            // listing) weighted by the GIVER's mindset — thoughtful planners
            // see intentional gifts rank up; last-minute users barely notice.
            s += IntentionalityScore.score(for: post) * context.mindset.intentionalityWeight

            // Layer 5 input — light exploration so the feed never goes static.
            s += Double.random(in: 0..<W.explore)

            let reason = reasons.max(by: { $0.weightedValue < $1.weightedValue })?.text
            scored.append((RankedCandidate(post: post, score: s, reason: reason), signals))
        }

        // ── Layer 5: greedy diversity re-rank ───────────────────────────────
        // Penalize picking the same author/category back-to-back (MMR-style)
        // so one Pinterest board — or the whole giftmaxxing_catalog — can't
        // monopolize a screenful. The 0.85 nudge wasn't enough when an entire
        // candidate page shared one author: repeats now sink hard, and an
        // author already holding 3 of the last 8 slots is halved on top.
        var pool = scored.sorted { $0.0.score > $1.0.score }
        var result: [RankedCandidate] = []
        result.reserveCapacity(pool.count)
        var recentAuthors: [String] = []
        var recentCategories: [String] = []

        while !pool.isEmpty {
            var bestIdx = 0
            var bestScore = -Double.infinity
            for (i, entry) in pool.prefix(12).enumerated() {
                var s = entry.0.score
                let author = entry.0.post.user
                if recentAuthors.suffix(3).contains(author) { s *= 0.6 }
                if recentAuthors.filter({ $0 == author }).count >= 3 { s *= 0.5 }
                if recentCategories.suffix(2).contains(entry.signals.category) { s *= 0.92 }
                if s > bestScore { bestScore = s; bestIdx = i }
            }
            let picked = pool.remove(at: bestIdx)
            result.append(picked.0)
            recentAuthors.append(picked.0.post.user)
            recentCategories.append(picked.signals.category)
            if recentAuthors.count > 8 { recentAuthors.removeFirst() }
            if recentCategories.count > 8 { recentCategories.removeFirst() }
        }

        return result
    }
}
