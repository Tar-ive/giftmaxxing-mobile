# Gift recommendation research — how the industry does it, what gifts change, and what we should build

> **Status: research deliverable (no code).** Commissioned to answer: what recommendation
> engines do major companies actually run, what is genuinely different about *gift*
> recommendation, how do we operationalize the four founder-named signals — (a) stable
> taste, (b) historical likes, (c) what they're into right now, (d) "a good gift is
> something they wouldn't buy for themselves" — and what should we upgrade in our stack
> (Titan Multimodal 1024-d embeddings in S3 Vectors, mean-of-liked-pins taste centroid,
> cosine kNN in `GET /recommendations`, blended with vibe/price/social/follow facets).
>
> **Method + evidence status.** Produced by a fan-out research harness: 5 search angles →
> 21 sources fetched → ~105 falsifiable claims extracted with direct quotes → adversarial
> verification. Verification completed for the first 5 claims (all **confirmed 3-0**, none
> refuted) before hitting a compute quota; remaining claims are quote-backed from primary
> sources (arXiv papers, engineering blogs, peer-reviewed journals) and internally
> consistent, but carry an *unverified* flag in §7. Read anything load-bearing before
> committing spend.

---

## 0. TL;DR

1. **Our retrieval shape is already correct.** Embedding kNN as candidate generation is
   *the* production pattern — YouTube's paper says serving "reduces to a nearest neighbor
   search in the dot product space" and that A/B results were insensitive to the ANN
   library (confirmed 3-0). S3 Vectors vs. anything fancier is not our bottleneck.
2. **What we're missing is the second stage.** Every major system is a funnel:
   *retrieval* (fast, coarse, millions→hundreds) → *ranking* (slow, precise, uses
   user×item interaction features that a dot product structurally cannot express). Our
   vector path currently returns raw cosine order; `scorePost`'s facets and the cosine
   score live in two parallel code paths instead of one funnel.
3. **A single mean centroid washes out taste.** Alibaba (ComiRec) and Pinterest
   (PinnerFormer/PinnerSAGE) both abandoned "one vector per user": real users hold
   several simultaneous interests, so represent a person as **multiple interest
   clusters** and retrieve per cluster. Notably, in Alibaba's case study, *gift shopping
   emerged as its own learned interest cluster*, distinct from personal taste.
4. **"Right now" = a short-term centroid blended with the long-term one** — not model
   retraining. Pinterest's TransAct (realtime last-100-actions transformer, +6% repins)
   and ByteDance's Monolith (minute-level parameter sync) are the heavyweight versions;
   the startup-scale version is time-decayed interaction weights plus a separate recent
   centroid with an adaptive blend, which the session-based literature (PAN) shows beats
   any fixed blend. Because we compute centroids at query time, freshness is nearly free
   for us — an actual structural advantage.
5. **The gift-specific science is an information problem, with a twist.** Waldfogel:
   gifting destroys 10–33% of value because givers lack recipient preference information,
   and the loss grows with social distance — but a giver who knows preferences *the
   recipient themselves is unaware of* can create value above cost. That is the economic
   formalization of factor (d) and of Giftmaxxing's whole premise: **the product is a
   taste-information pipe from recipient to giver.**
6. **Factor (d) has a validated recipe — and a validated caveat.** The recsys
   serendipity literature operationalizes "wouldn't buy it themselves" as *distance from
   the user's expected set*, with utility that is **unimodal**: too close = obvious
   ("milk and bread"), too far = irrelevant. Retrieve in a **sweet-spot distance band**,
   not top-k nearest. Our challenge engine already has the band constants
   (twin < 0.35, same-vibe < 0.55 cosine distance). The caveat: psychology consistently
   finds recipients prefer *requested* gifts over surprises, prefer feasible over
   aspirational, and value long-term ownership over unwrap-wow — so implement (d) as
   "novel *within* their taste, never a duplicate," and build wishlist/hint capture, not
   surprise-maximization.
7. **Rank by a real outcome, not clicks.** YouTube ranks on expected watch time because
   CTR promotes clickbait (confirmed 3-0). Our equivalent north star: saves, outbound
   product clicks, challenge "yes" votes, and (eventually) "I gave this" confirmations —
   not impressions or taps.
8. **Cheapest high-leverage upgrades, in order:** unify the funnel (vector retrieval →
   facet re-rank), time-decay + short-term centroid, multi-cluster taste, per-recipient
   gift mode with the serendipity band + dedupe-against-owned, negative signals (hides)
   as a subtracted centroid, then Thompson-sampling exploration. All fit Lambda + S3
   Vectors with zero new infrastructure.

---

## 1. What the industry actually runs

### 1.1 The universal shape: retrieval → ranking funnel

Across YouTube, Alibaba, JD, Facebook, LinkedIn, DoorDash, Pinterest, the architecture is
the same 2×2: offline vs. online environments × candidate retrieval vs. ranking
(Eugene Yan's cross-company survey). Retrieval is deliberately coarse — "narrow down
millions of items into hundreds of candidates… a 99.99% reduction" — and ranking then
spends its compute budget on only those survivors.

- **YouTube (2016, confirmed 3-0):** two networks — candidate generation retrieves
  hundreds from millions off the user's activity history; a separate ranking network
  scores them down to dozens. Serving-time candidate generation is literally ANN search
  over embeddings, and the ANN algorithm choice didn't move A/B results.
- **Pinterest ads (2026 engineering blog):** feature expansion → retrieval → lightweight
  ranking (two-tower dot product, O(10K–100K) docs/request) → heavy ranking → auction.
  Two-tower became the industry standard for early funnel stages because dot-product
  scoring "scan[s] millions of candidates in mere milliseconds."
- **The known ceiling of our current shape:** Pinterest's stated reason for moving
  *beyond* two-tower in later stages is that user and item towers only meet at the dot
  product, so the score can't use user×item interaction features ("User A has clicked
  an ad from Advertiser B five times in the last hour"). Their replacement cut offline
  loss ~20% but required a GPU serving stack (p90 driven from 4000ms → 20ms) — Pinterest
  scale, not ours. The transferable lesson: **keep cosine for retrieval; add the
  user×item features in a cheap second-stage scorer** (which is exactly what `scorePost`'s
  facets are — they just need to run *on top of* the vector candidates).

### 1.2 User representation: from one vector to many

- **PinSage (KDD '18, confirmed 3-0):** production GCN over the pin-board graph;
  embeddings fuse graph structure *and* content features. Trained on 3B nodes / 18B
  edges — the *architecture* doesn't transfer to us, but the *idea* does: item
  similarity should eventually reflect co-save behavior, not just visual similarity.
  Alibaba does the analogous thing with random walks over a session-built item graph.
- **ComiRec (Alibaba, KDD '20):** a single user embedding "suffers from the lack of
  expressiveness… customers usually have several kinds of items in their minds." They
  extract K=4 interest vectors per user (capsule routing or self-attention), retrieve
  top-N per interest via Faiss, then merge with a **tunable diversity factor λ**: on
  Amazon data, λ 0→0.25 raised Diversity@50 from 23% → 55% while Recall@50 fell only
  8.47% → 8.03%. And their case study found one user's four learned interests were
  *sweets, gift boxes, phone cases, accessories* — gift-shopping separated itself from
  personal taste with no labels.
- **PinnerFormer (KDD '22):** transformer over the user's action sequence, but trained
  with a "dense all-action loss" to predict *14-day future engagement*, not next action.
  Payoff: **once-a-day batch embeddings nearly match realtime embeddings** — i.e., a
  small team gets most of the value of sequence modeling without streaming infra.

### 1.3 "Right now": realtime signals and model freshness

- **Pinterest TransAct (Homefeed):** last 100 actions (pin embedding + action type +
  timestamp) fed as a sequence into ranking. Online: +6% repins overall, +11% for
  non-core users, −10% hides. Two operational warnings that transfer directly:
  (1) a naive version was *over*-responsive to the last day of actions and hurt
  diversity — they fixed it with random time-window masks; (2) CPU latency rose >20×,
  forcing GPU serving. Their design doctrine: realtime sequence = short-term interest,
  *complementary to* batch long-term embeddings, mattering most for new/casual users.
- **ByteDance Monolith:** online training with minute-level sparse-parameter sync;
  shorter sync intervals monotonically raised AUC, and online beat batch training by
  double-digit AUC% in a live test. The thesis — freshness is worth more than
  fault-tolerance — is real, but the Kafka+Flink apparatus is the anti-pattern at our
  scale. **Our advantage:** we compute the taste centroid *at query time from stored
  interactions*, so our "model" is always fresh by construction; we only need the
  *inputs* (interaction log with timestamps) to be fresh.
- **YouTube's freshness trick:** users prefer fresh content; models trained on history
  are biased to the past; fix by feeding example age as a training feature, zeroed at
  serving. Our no-ML equivalent is what `scorePost` already does (365-day recency decay)
  plus an engagement-velocity ("trending") term.
- **Session literature (PAN, and Pinterest's RecSys '22 paper):** short-term interest
  should not be just the last item — use the recent *window* with time-interval
  awareness (big gaps signal interest drift), and blend long/short with a **learned,
  per-user gate**; every fixed blend (average, concat, Hadamard) lost to the adaptive
  gate. Startup translation: interaction weight = `w_action × exp(−Δt/τ)`, two centroids
  (all-time, last-N-days), blend coefficient driven by how active/divergent the recent
  window is.

### 1.4 Exploration, bandits, and humility at small scale

- Bandits fit **low-traffic and fast-changing catalogs** because they update
  incrementally instead of waiting for batch retrains (Eugene Yan's bandits survey).
  Thompson Sampling is the default under delayed feedback.
- **Deezer:** semi-personalized bandits over ~100 user *clusters* beat fully per-user
  bandits — pooling gives each bandit enough feedback. That's our cold-start pattern:
  cluster onboarding profiles (vibes × budget × role), run per-cluster exploration.
- **Spotify:** ran exploration *inside* the funnel — bandit only over the ~100 most
  relevant retrieved items so exploration can't wreck UX. Also: their popularity
  baseline beat AdaBoost/Random Forest for podcast cold-start. **Never skip the
  popularity baseline.**
- **Twitter:** offline metrics and online behavior diverged for exploration policies
  (greedy won offline PR-AUC, lost live CTR; bandits the reverse). Don't pick policies
  from offline replays of biased logs.
- **Apple App Store:** two-stage bandit (LCB in recall, Thompson in ranking) + uniform
  sampling of cold items to fight confirmation bias.
- **Netflix (RecSys '22):** in a real-time in-session recommender, "machine learning
  only plays a small part" — most of the work is the systems around it. Comforting and
  true: our moat is signal capture and product design, not model exotica.

### 1.5 What transfers at our scale (~10²–10⁴ users, ~10²–10⁵ items)

| Pattern | Adopt? | Form it takes for us |
|---|---|---|
| Retrieval→ranking funnel | **Yes, now** | S3 Vectors kNN over-fetch → facet/business re-rank → policy layer (diversity, dedupe, ads cadence) |
| Two-tower learned towers | Not yet | Titan embeddings *are* our item tower; "user tower" = engineered centroid(s). Learn towers only when we have real interaction volume |
| Multi-interest user rep | **Yes, now** | k-means/mean-shift over liked-pin embeddings → 2–4 cluster centroids, retrieve per cluster, λ-merge |
| Sequence models (PinnerFormer/TransAct) | No (pattern only) | Time-decayed weights + short-term centroid + adaptive blend; revisit transformers at >10⁵ DAU |
| Graph embeddings (PinSage) | No (pattern only) | Later: co-save/co-like adjacency as a re-rank feature |
| Online training (Monolith) | No | Query-time centroids already give us freshness for free |
| Bandits | **Soon** | Keep score jitter today; Thompson sampling on the retrieved candidate set; cluster-level (Deezer-style) for cold start |
| Objective ≠ clicks | **Yes, now** | Rank/evaluate on saves + outbound clicks + challenge-yes, not taps |

---

## 2. What is actually different about gifts

This is where generic recsys advice stops and our defensible product begins.

### 2.1 The economics: gifting is an information problem

Waldfogel (AER 1993) — the canonical "deadweight loss of Christmas" result:

- Holiday gifts destroy **10–33% of value** (recipient valuation vs. price paid) because
  the chooser isn't the consumer.
- **Loss scales with social distance:** friends' gifts yield 98.8% and significant
  others' 91.7% of price paid, vs. 64.4% (aunts/uncles) and 62.9% (grandparents).
  Grandparents rationally give cash 42.9% of the time; friends ≤6%.
- The flip side, and our thesis statement: *"The better the giver knows the recipient's
  preferences — including, possibly, preferences the recipient is unaware of — the more
  likely it is that the giver will choose a gift that the recipient values above its
  cost and will thereby create value through giving."*

**Product translation.** Giftmaxxing's job is to synthetically close social distance:
give an aunt the taste information a best friend has. The users who need us most
(distant givers) are precisely those with the least recipient signal — so *recipient-side
signal capture* (linked boards, challenges, wishlists) is the core asset, and every
distant-giver flow should lean on it hardest. Caveat for honesty: the study is 86 Yale
undergrads; treat magnitudes, not the direction, as soft.

### 2.2 The psychology: the Gift Gap, and where the founder's factor (d) needs refining

A 2024 meta-analysis (Psychology & Marketing; 153 effects, 114 studies, 29 papers)
confirms a persistent **giver–recipient evaluation gap**, moderated by gift, occasion,
and dyad characteristics — empirical license to make the recommender occasion-aware and
relationship-aware, not just taste-aware. The gap is *worst* for sentimental,
privately-consumed gifts between friends (flag these as high-risk, don't push them by
default).

The specific asymmetries (Galak, Givi & Williams 2016; Gino & Flynn 2011):

| Givers believe | Recipients actually | Ranker consequence |
|---|---|---|
| Surprise/unrequested gifts show thoughtfulness | Prefer **explicitly requested** gifts; find them *more* thoughtful | Wishlist/"hint" capture beats surprise-maximization; weight recipient-expressed items heavily |
| The unwrapping moment is what counts | Value the gift **over the period of ownership** | Optimize predicted long-term use, not visual wow |
| Desirable > feasible (impressive, high-spec) | Prefer **feasible/usable** over aspirational | Cap the "aspirational" boost; practical items are undervalued by givers, not by recipients |
| More expensive ⇒ more thoughtful | No such link | Don't let price ride as a proxy for quality in gift mode |
| Material objects | More happiness from **experiential** gifts | Catalog should include experiences, not only products |
| Cash is a lame gift | Appreciate money more than givers think | Keep gift cards/cash-adjacent options un-penalized |

**So factor (d) — "something they wouldn't get themselves" — survives, but reframed.**
The economics says the winning gift exceeds the recipient's own willingness-to-pay or
awareness (they wouldn't have bought it *yet*), NOT that it lies outside their taste or
their expressed wishes. The failure mode to engineer against is "obvious duplicate"
(they own it / would buy it this week anyway), not "insufficiently surprising."

### 2.3 Gift recsys as an academic field

A peer-reviewed survey exists — Mohseni, Sajedi & Hussain, *Gift recommendation systems:
a review* (Electronic Commerce Research, Dec 2023). It frames the field's defining
problem as **prediction error across the giver/recipient dyad** and derives evaluation
metrics from the psychology/marketing/anthropology literature. Two useful takeaways:
(1) the field is tiny (~3 citations as of mid-2026) — there is no incumbent playbook to
copy, which is an opportunity; (2) its bibliography (asymmetric price/appreciation
beliefs, "Give them what they want," "The 'perfect gift'…", Gift-me 2018) is the
starting reading list for whoever builds our gift-mode ranker.

### 2.4 Whether givers will even accept AI gift advice (adoption science)

A 2024 Psychology & Marketing paper (5 experiments, UK samples) on AI gift-recommendation
tools, directly about products like ours:

- Givers are **less willing to use an AI tool for close friends** than distant "hi-bye"
  friends — resistance is highest exactly where stakes are highest. Mechanism: gifts
  serve two motives — *preference matching* AND *relational signaling* ("this gift shows
  I know you") — and people expect AI to fail the signaling motive for close ties.
- **Tested fix:** giving the AI *turn-taking* — asking about the recipient one question
  at a time, conversationally, instead of a static form — significantly raised expected
  preference-matching for close-friend gifting and, through it, tool adoption. This is
  strong external validation for running recipient profiling through **Maxi as a
  dialogue**, not a settings page.
- For **distant recipients**, broadly appealing / trending / demographically popular
  items satisfy the preference-matching motive — i.e., popularity-based recs are not a
  cop-out for the aunt-buying-for-nephew case; they're what the science prescribes.
- **Anonymous-gifting occasions (Secret Santa) are a low-resistance wedge:** when the
  giver's identity isn't disclosed, close-relationship givers become *more* willing to
  use AI recommendations.
- Their critique of existing tools: they ingest occasion + recipient demographics and
  **ignore the giver–recipient relationship** — so make *closeness* a first-class input
  (we already collect `RelationType` per recipient; Waldfogel's yield table even
  suggests its prior).

### 2.5 The serendipity/unexpectedness literature — the algorithmic core of factor (d)

- **The "milk and bread" problem** (Adamopoulos & Tuzhilin, ACM TiiS 2014): an accurate
  recommendation can be worthless because the purchase would happen anyway — the exact
  recsys formalization of "they'd buy it for themselves." Their construction:
  build the user's **expected set** (past transactions + items formally similar to
  them), score candidates by **distance from that set**, and note that utility is
  **unimodal in that distance** — each user has a sweet-spot surprise level; too close
  is obvious, too far is irrelevant. Empirically, *average* distance to the expected set
  beat centroid distance, and their method beat kNN/MF baselines on unexpectedness
  **without accuracy loss** (99% of 2,160 configurations).
- **Serendipity = surprise × relevance** (Kaminskas & Bridge, ACM TiiS 2016): surprise
  is operationalized as **minimum distance from the user's profile items**. Novelty is
  `1 − popularity(i)` or `−log p(i)` (long-tail bonus). The dominant deployment technique
  is **greedy re-ranking** (MMR-style: `α·relevance + (1−α)·distance-to-already-picked`)
  bolted onto any base recommender — explicitly praised for ease of deployment, i.e., a
  Lambda-side re-rank over our kNN output, no infra. Known cost: every beyond-accuracy
  re-rank lowers offline recall a little (a 0.05 recall loss bought a 30% coverage gain
  in their runs) — and offline evals are popularity-biased against serendipity, so judge
  it online.
- **PURS (RecSys 2020, A/B-tested at Alibaba-Youku):** model the user as **multiple
  interest clusters** (Mean Shift over historical item embeddings); unexpectedness =
  cluster-size-weighted distance from the candidate to those clusters; final utility =
  `relevance + f(unexpectedness)·personalized_factor` with **f(x) = x·e^(−x)** — a
  bounded unimodal boost so moderate surprise wins and extreme novelty is penalized.
  Online: +3.74% video views, +4.63% time spent. This is the closest thing to a
  production-proven blueprint for our gift-mode scorer.
- **Amazon (RecSys '22), "Don't Recommend the Obvious":** train to estimate point-wise
  mutual information (PMI) rather than raw co-occurrence, so globally popular items don't
  crowd out personally-informative ones. Our cheap analog: divide (or shrink) an item's
  social-proof boost by its global popularity when it's being pitched *as a gift insight*.
- **Users actually like this** (Taobao serendipity study, 3,000+ users, Mobile Taobao):
  significant causal paths from novelty/unexpectedness/relevance/timeliness →
  perceived serendipity → satisfaction AND purchase intention; a serendipity-oriented
  algorithm beat relevance- and novelty-oriented ones on user perception. Bonus: the
  effect is moderated by user **curiosity** — the dose of surprise should be
  personalized (some recipients are adventurous, some aren't; our onboarding
  `GiftDifficulty` and `GiftStyle` are usable priors for that dial). The dataset is
  public if we ever want to calibrate a serendipity metric.

---

## 3. Operationalizing the four factors

The unifying model: represent every person (user *or* linked recipient) not as one
vector but as a small **taste object**, computed at query time from logged interactions:

```
TasteObject {
  longTermClusters: 2–4 centroids over liked/saved-pin embeddings (k-means/mean-shift),
                    each with weight = Σ time-decayed interaction weights
  shortTermCentroid: decayed mean over the last N days / last M interactions
  negativeCentroid:  mean over hides / challenge-"no" swipes
  expectedSet:       the raw liked/saved/owned item embeddings themselves (for min-distance)
  priors:            vibes, budget, dealPrefs, difficulty/style (onboarding), popularity fallback
}
```

**(a) Stable taste → `longTermClusters`.** The mean-of-everything centroid we compute
today literally averages a person who loves both cottagecore kitchenware and cyberpunk
gaming gear into a vector matching neither (ComiRec's core argument; PinnerFormer's
motivation). Cluster the liked-item embeddings; retrieve kNN per cluster; merge with
ComiRec's λ-greedy aggregation (large diversity gain, ~nil recall cost). Onboarding
vibes act as priors for cold-start cluster seeds (our `pickSeedPins` already maps vibes
→ seed pins — extend it to seed *clusters*).

**(b) Historical likes → interaction-weighted everything, and user×item features in
ranking.** YouTube's ranking finding: the most predictive features are the user's *own
previous interactions with this item and similar items*. We already weight save > like >
comment (1.6/1/0.6) — keep that, add: outbound product click (strong), dwell (weak),
hide (negative). In the second-stage scorer, add user×item features the dot product
can't see: "user previously engaged this author/merchant/category," "user hid something
in this cluster," "price relative to user's revealed band."

**(c) Right now → `shortTermCentroid` + adaptive blend + freshness features.**
- Interaction weight `w × exp(−Δt/τ)` with τ ≈ 30–60 days for the long-term object, plus
  a short-term centroid over the last session / 7 days.
- Blend `taste = β·short + (1−β)·long` with β *adaptive per user* (PAN's gated-fusion
  result): high recent activity in a coherent direction → β up; sparse/stale recent
  activity → β down. A logistic function of (recent-interaction count, mean time gap)
  is enough — no learning required to start.
- Guardrails Pinterest learned the hard way: don't over-react to the last day
  (their time-window masks); keep diversity floors.
- Item-side freshness: keep `scorePost`'s recency decay; add an engagement-velocity
  ("trending this week") feature — which also serves the distant-giver popularity
  prescription from §2.4.
- Occasion time is a gift-unique "right now": `eventBoost` (0→1 over 45 days before a
  logged event) already exists — route it to boost *recipient-taste-matched* candidates
  and tighten the budget prior as the date approaches.

**(d) "Wouldn't buy it themselves" → a serendipity band scored against the *recipient's*
taste object, with a duplicate veto and a wishlist override.**
- **Relevance:** cosine to the recipient's cluster centroids (their taste, not the
  giver's).
- **Surprise:** min distance from the recipient's `expectedSet` (Kaminskas & Bridge) or
  cluster-weighted distance (PURS).
- **Unimodal boost:** `utility = relevance + surprise·e^(−surprise/δ*)` — the sweet-spot
  band. We already have empirical cosine-distance bands in production (challenge engine:
  twin < 0.35, same-vibe < 0.55): **twin-band items are the "milk and bread" — veto or
  down-rank them in gift mode** (they own it or would buy it themselves); the
  0.35–0.55 band is the gift zone; beyond ~0.62 (our visual-search relevance gate) is
  noise.
- **Personalized surprise dial δ\*:** from recipient curiosity proxies —
  `GiftDifficulty`, `GiftStyle`, breadth of their cluster structure.
- **Novelty/PMI term:** shrink social-proof by global popularity so we recommend
  *informative* items, not just bestsellers — except for distant dyads, where popular
  items are the right answer (§2.4).
- **Psychology overrides (§2.2):** anything the recipient explicitly requested/hinted
  outranks everything (requested > surprise); cap aspirational-impractical items;
  include experiences; flag sentimental/private gifts as high-variance rather than
  boosting them.

**The dyad, explicitly.** `Recipient` in `web/lib/events.ts` already carries
`sourceUser` + `pinSeeds` (recipient taste seeds) and `relation`. Gift mode =
`GET /recommendations` with the **recipient's** taste object for relevance+surprise, the
**giver's** budget/deal prefs as constraints, `relation` as the closeness input
(distant → lean popular; close → lean personal + push wishlist capture, since close
givers distrust AI picks), and occasion/eventBoost as the temporal frame. The
poll-scoring code already computes yes-centroid vs. no-centroid deltas — the same
mechanic gives us recipient negative signals from challenge swipes.

---

## 4. Proposed architecture (target state, no code)

```
                      ┌──────────── RETRIEVAL (S3 Vectors, over-fetch ~5×) ───────────┐
 taste object ──────▶ │ kNN per long-term cluster  +  kNN for short-term centroid     │
 (user or recipient)  │ + trending/popularity candidates  +  sponsored candidates     │
                      └──────────────────────────┬─────────────────────────────────────┘
                                                 ▼
                      ┌──────────── RANKING (Lambda, ~200–500 candidates) ────────────┐
                      │ blend: cosine relevance · facet score (occasion/eventBoost,   │
                      │ budget-fit, audience, category) · user×item history features  │
                      │ · quality score · freshness/velocity · − negativeCentroid sim │
                      │ gift mode adds: unimodal surprise boost, twin-band veto,      │
                      │ wishlist override, popularity/PMI shrink, closeness policy    │
                      └──────────────────────────┬─────────────────────────────────────┘
                                                 ▼
                      ┌──────────── POLICY / RE-RANK (list-level) ─────────────────────┐
                      │ MMR diversity (α·score + (1−α)·distance-to-picked) · seen/hide │
                      │ dedupe · ads cadence + frequency caps · exploration (jitter    │
                      │ now → Thompson sampling over the candidate set later)          │
                      └────────────────────────────────────────────────────────────────┘
```

Everything above runs in the existing Lambda + S3 Vectors + DynamoDB stack at
candidate-set sizes of a few hundred — no OpenSearch, no GPUs, no streaming.

**Signals to start logging now** (the data moat; each is cheap and none can be
backfilled later): per-interaction timestamps (required for every temporal idea above),
impressions (required for any honest CTR/bandit math), hides + challenge-no (negative
centroid), outbound product clicks (our "watch time"), wishlist/hint capture
("drop a hint" is directly justified by requested>surprise), recipient links + per-
recipient challenge results, and eventually "I gave this → did it land?" feedback loops
(the only ground truth for gift success that exists anywhere; nobody else has it).

**Evaluation.** North-star per §1.4/§2.2: save rate + outbound click rate + challenge-yes
rate (and gift-confirmed when it exists), never raw taps. Online interleaving/A-B over
offline replay (Twitter's divergence warning); expect serendipity features to look
*worse* offline (popularity bias) — judge them on live satisfaction/purchase-intent
proxies, which the Taobao study shows they move.

---

## 5. Prioritized roadmap

| P | Upgrade | What it is | Why (evidence) | Cost |
|---|---|---|---|---|
| **P0** | **Unify the funnel** | Vector kNN (over-fetch) as the *only* candidate source when vectors exist; run `scorePost` facets + quality as the ranking stage on those candidates instead of the parallel facet path | Universal industry shape (§1.1, confirmed); two-tower's blind spot needs a second stage | S |
| **P0** | **Timestamps, impressions, hides** in the interactions log | Prereq for everything temporal + honest metrics + negative centroid | §1.3, §4 | S |
| **P1** | **Time-decayed + short-term centroid, adaptive blend** | Decayed weights (τ≈45d); last-7-day centroid; logistic β | PAN gated fusion; TransAct short/long complementarity; PinnerFormer batch≈realtime | S–M |
| **P1** | **Multi-cluster taste** | k-means (k≤4) over liked embeddings; retrieve per cluster; λ-greedy merge | ComiRec (+diversity ~2×, recall ~flat); PinnerSAGE | M |
| **P1** | **Gift mode (per-recipient)** | Recipient taste object + serendipity band (`x·e^(−x)` boost), twin-band veto, closeness policy, wishlist override; reuse challenge bands + `Recipient.pinSeeds` | Waldfogel; PURS (+3.7% online); Adamopoulos unimodality; requested>surprise; AI-adoption closeness findings | M |
| **P1** | **Maxi turn-taking recipient profiling** | Conversational one-question-at-a-time recipient intake feeding `pinSeeds`/interests | Experimentally raises adoption for close-friend gifting (§2.4) | M |
| **P2** | **MMR diversity re-rank + PMI/popularity shrink** | List-level greedy re-rank; social-proof ÷ global popularity in gift mode | Kaminskas & Bridge; Amazon PMI | S |
| **P2** | **Thompson-sampling exploration** | Replace jitter; per-item Beta posteriors over the retrieved set; cluster-level (Deezer) priors for cold start | §1.4 | M |
| **P3** | **Co-engagement graph features** | Co-save adjacency as a ranking feature (PinSage-lite) | §1.2 | M–L |
| **P3** | **Learned two-tower / sequence models** | Only at real traffic; batch PinnerFormer-style if ever | §1.2–1.3 | L |

(S ≈ days, M ≈ 1–2 weeks, L ≈ month+, one engineer/agent. Nothing above requires new
AWS services; the only new spend is negligible extra S3 Vectors queries from
per-cluster retrieval.)

---

## 6. What's unique about *us* — the strategic read

1. **The recommendation is for someone who isn't the user.** Every generic engine
   optimizes "user will engage"; ours must optimize "recipient will value across
   ownership," using the giver only for budget/occasion/relationship constraints. The
   dyad — not the algorithm — is the defensible layer, and our data model already has it.
2. **Our data moat is recipient-side signal that Amazon/Pinterest don't have:** linked
   boards, challenge swipes answering "would they like THIS?", hints/wishlists, and
   post-gift outcomes. Every roadmap item that captures more of it compounds.
3. **The deadline is a feature.** Occasions give us urgency, budget, and a natural
   re-engagement loop (event calendar → reminders → gift mode) that self-purchase feeds
   lack; `eventBoost` is the seed of it.
4. **The four founder factors are all real, with one refinement:** (a),(b),(c) map
   cleanly onto long-term/historical/short-term representations the industry has
   converged on; (d) is economically correct (Waldfogel's value-creation condition) but
   should be implemented as *novel-within-taste + never-a-duplicate + requested-beats-
   surprise*, with a personalized surprise dial — not as surprise-maximization.

---

## 7. Sources

**Confirmed by 3-0 adversarial verification:**
- Ying et al., *Graph Convolutional Neural Networks for Web-Scale Recommender Systems*
  (PinSage), KDD 2018 — arxiv.org/abs/1806.01973 (2 claims)
- Covington, Adams & Sargin, *Deep Neural Networks for YouTube Recommendations*,
  RecSys 2016 — research.google/pubs/deep-neural-networks-for-youtube-recommendations
  (3 claims)

**Quote-backed primary sources (verification interrupted by quota; treat as unverified):**
- Pancha et al., *PinnerFormer: Sequence Modeling for User Representation at Pinterest*,
  KDD 2022 — arxiv.org/abs/2205.04507
- Xia et al. (Pinterest), *TransAct / realtime user actions in Homefeed ranking* —
  medium.com/pinterest-engineering/how-pinterest-leverages-realtime-user-actions…
- Pinterest Engineering, *Beyond Two Towers* (ads lightweight ranking), 2026 —
  medium.com/pinterest-engineering/beyond-two-towers…
- Liu et al. (ByteDance), *Monolith: Real Time Recommendation System With Collisionless
  Embedding Table*, 2022 — arxiv.org/abs/2209.07663
- Cen et al. (Alibaba/Tsinghua), *Controllable Multi-Interest Framework for
  Recommendation* (ComiRec), KDD 2020 — arxiv.org/pdf/2005.09347
- Zhu et al., *PAN: Personalized Attention Network for session-based recommendation*,
  2020 — arxiv.org/pdf/2006.15346
- Eugene Yan, *System Design for Recommendations and Search*; *RecSys 2022 highlights*
  (Amazon PMI, Apple two-stage bandit, Spotify exploration, Netflix in-session);
  *Bandits for Recommender Systems* (Deezer, Thompson vs UCB, Twitter offline/online
  divergence) — eugeneyan.com
- Adamopoulos & Tuzhilin, *On Unexpectedness in Recommender Systems*, ACM TiiS 2014 —
  dl.acm.org/doi/10.1145/3308558.3313469 (fetched version)
- Kaminskas & Bridge, *Diversity, Serendipity, Novelty, and Coverage*, ACM TiiS 2016 —
  dl.acm.org/doi/10.1145/2926720
- Li et al., *PURS: Personalized Unexpected Recommender System*, RecSys 2020 —
  dl.acm.org/doi/10.1145/3383313.3412238
- Chen et al., *Serendipity study on Mobile Taobao* (user survey + dataset), WWW 2019 —
  ceur-ws.org / dl.acm.org
- Waldfogel, *The Deadweight Loss of Christmas*, American Economic Review 1993 —
  jmvidal.cse.sc.edu/library/waldfogel93a.pdf
- *Gift Gap meta-analysis* (153 effects / 114 studies / 29 papers), Psychology &
  Marketing 2024 — onlinelibrary.wiley.com/doi/10.1002/mar.21981
- Galak, Givi & Williams, *Why Certain Gifts Are Great to Give but Not to Get*, Current
  Directions in Psychological Science 2016 — journals.sagepub.com/doi/10.1177/0963721416656937
- Gino & Flynn, *Give them what they want: The benefits of explicitness in gift
  exchange*, JESP 2011 — via researchgate.net
- *AI gift recommendation tools and giver–recipient closeness* (5 experiments),
  Psychology & Marketing 2024 — onlinelibrary.wiley.com/doi/10.1002/mar.22050
- Mohseni, Sajedi & Hussain, *Gift recommendation systems: a review*, Electronic
  Commerce Research 2023 — link.springer.com/article/10.1007/s10660-023-09790-6

---
---

# Part 2 — Cold start and the two entry modes (codebase signal audit)

> Added after founder review of Part 1. Two directives: (1) we are not an established
> platform, so the algorithm must be optimized for **brand-new users**; (2) users arrive
> in exactly two postures — **as a recipient** (someone sent them a swipe challenge, and
> their swipes deterministically sharpen our model of what they like) or **as a giver**
> (they came to find a gift for a specific friend, or to pledge in a gift pool) — and the
> recommender should specialize for each. Part 2 grounds that design in what the code
> and Terraform tables *actually* collect today (audited Jul 2026, `infra/*.tf`,
> `infra/src/handler.mjs`, `Giftmaxxing/` iOS app). It also corrects Part 1 where the
> audit proved it stale.

## 8. Signal inventory — what we already have and collect

### 8.1 Corrections to Part 1 (the iOS app is further along than the web ranker)

- **The retrieval→ranking funnel already exists — on the device.**
  `Giftmaxxing/Services/Recommendation/OnDeviceRanker.swift` is an explicit 5-layer
  Instagram-style ranker: server retrieval (byFeed window / S3 Vectors kNN) → integrity
  gate (seen de-dup + `ContentQuality`) → `scorePost`-parity facets → personalization
  (vibe taste, price fit, author affinity, negative-category penalty, **cosine to the
  taste centroid over int8 vectors cached from `GET /vectors`**) → exploration + MMR
  diversity (author/category spacing). Part 1's "P0: unify the funnel" is largely DONE,
  client-side; what remains is making the *server* paths (`/recommendations`, challenge
  decks) consistent with it.
- **Time-decayed taste already exists.** `TasteProfileStore.swift` keeps decayed
  aggregates with a **14-day half-life** — vibes, author affinity, category affinity,
  price preference — plus a 3,000-item seen set and a 24-item `seedKeys` list (newest
  strong signals first). Part 1's "P1: time-decay" is done in aggregate form; what's
  missing is the *two-timescale* split (stable vs. right-now) and multi-cluster taste.
- **Negative signals exist and are weighted** (hide −1.2, unlike −1.0, unsave −1.6) —
  but left-swipe hides are **deliberately local-only** ("the strongest explicit negative
  signal the app has — they feed the on-device taste profile but stay local",
  `SwipeView.swift`). The server never sees them (see §8.4 privacy note).
- **The interaction vocabulary changed.** The live verbs are: `impression` (on-device
  only), `open`, `like`/`unlike` (a right/left swipe maps to like/hide), `save`/`unsave`,
  plus **add-to-swipe-list** (queue an item to send a friend) and **pledge** (pool
  contribution). Feed "likes/comments" as social UI are legacy; `scorePost`'s
  social-proof term still reads seeded `likes` counts.

### 8.2 The founder's five, mapped to reality

| Founder's word | What it actually is in the stack | Persisted where |
|---|---|---|
| **Photos** | Share-extension captures (`GiftmaxxingShare` → app-group inbox → `CaptureInbox`) routed to `POST /visual-search` (Titan embed → kNN) or pool creation. **The query embedding is computed and then discarded** — see gap G3. | S3 media only if pooled; embedding: nowhere |
| **Taste profile** | On-device `TasteProfileStore` (decayed vibes/author/category/price + seedKeys + seen) + consult cold-start (`PersonalizationStore`: genderPref, ≤6 vibes) + graph `interest` nodes with `LIKES` edges | Device JSON + `graph` table |
| **Seen** | Impressions → on-device seen-set (feeds de-dup) + `analytics` `feed_impression`/`feed_dwell` (viewport dwell!) | Device + `analytics` (TTL'd) |
| **Words** | Maxi chat (`maxi_message_sent`, server `/maxi` with long-term `MEM#` memory rows in the graph table) + `search_query` events | `graph` (MEM#) + `analytics` |
| **Pledged** | Pool contributions — `pools` table `CONTRIB#<ts>` rows `{userId, name, amount, at}` under a pool META carrying occasion/title/goal | `pools` table |

### 8.3 Full inventory (table → what's in it → does ranking use it today?)

| Store | Contents relevant to recs | Used by ranking today? |
|---|---|---|
| `interactions` (DDB) | `open/like/unlike/save/unsave` with timestamps, batched from the phone, **under a stable anonymous id pre-signup** (`anon-<uuid>`, `InteractionQueue.anonymousUserId`) | Server vector path derives seeds from it; device profile is the richer copy |
| `analytics` (DDB, byType GSI, TTL) | The full behavioral stream: session lifecycle, `feed_impression`, `feed_dwell`, scroll depth/velocity, `swipe_card_shown`, `swipe_right/left`, `swipe_decision_time`, `swipe_velocity`, `swipe_hesitation`, `swipe_deck_complete`, `swipe_undo`, `maxi_*`, `product_view`, `product_affiliate_click`, `search_query`, `search_result_tap` | **No** — collected, never folded into taste (gap G6) |
| `challenges` (DDB) | Per challenge: seed item, **int8-packed seed vector**, banded deck snapshot (twin/vibe/probe + distances); per response: guest name/handle/**birthday**/genderPref, swipes `{id, dir, dwellMs}`, **verdict** `{score, label, weightedApproval, centroidDelta, topCategories, priceBand (min/median/max), favoriteId (max-dwell), variantPicks (yes-swiped twins = direct buy candidates)}` | Verdict shown to sender; **guest's own taste is not persisted for the guest** (gap G1) |
| `connections` (DDB) | Soft profiles owned by the **sender**: guestName, birthday, genderPref, vibes (=topCategories), **`seeds` = up to 8 yes-swiped pin keys**, verdict stats; claimable anonId→userId (`/connections/claim`) | `seeds` usable as recipient kNN seeds; bundles endpoint reads birthday as deadline |
| `graph` (DDB) | Nodes: user/recipient/event/interest/soft; edges: `LIKES` (→interest), `COLLECTED` (→soft); Maxi `MEM#` memories. "Hard onboarding + soft swipe-derived taste" | Read by `/graph` + Maxi; not by the ranker |
| `events` (DDB) | Personal + shared occasions incl. **auto-captured soft-profile birthdays from challenges**, budgets; powers `/events/upcoming` → `eventBoost` | Yes — occasion facet ramps as dates approach |
| `knowledge` (DDB) | **Reddit-mined ranked gift ideas + co-occurrence bundles per recipient type** (mom, coworker, couple…) | Maxi/bundles only — not in feed retrieval (gap G7) |
| `pools` (DDB) | META (title/occasion/goal/raised) + MEMBER + **CONTRIB pledges** + chat MSGs | **No** (gap G8) |
| `users` (DDB) | Onboarding `UserProfile`: role, difficulty, style, interests, dealPreferences, recipients (with `sourceUser`/`pinSeeds` slots), events, genderPref | Vibes → consult cold-start; deal prefs unused |
| S3 Vectors `pins` | 1024-d Titan MM embeddings + metadata (title/price/domain/category/link) | Yes — kNN retrieval, challenge decks, visual search, on-device cosine |
| Device: `TasteProfileStore` | Decayed vibe/author/category/price affinities (± signs), seen set, seedKeys(24) | **Yes — the primary personalization engine** |
| Device: `SwipeListStore` | "Saw it, thought of you" queue — items a giver picked **for a specific friend** | Local-only, UserDefaults, no server sync (gap G5) |
| Device: `VectorStore` | int8 vectors cached from `GET /vectors` for on-device cosine | Yes |

The pre-signup anonymous identity + `/connections/claim` re-keying means **taste can
accrue before an account exists and survive conversion** — the exact plumbing both entry
modes need.

## 9. Specializing the recommender for the two entry modes

Detect the mode at session start from the deep link (challenge link / pool invite /
event reminder / organic open) and log it as an `entry_mode` analytics property — every
downstream choice (retrieval source, exploration dose, what to ask next) branches on it.

### 9.1 Mode R — recipient-entry (they got a swipe challenge)

One completed deck (~14 swipes with dwell) is worth more than weeks of passive feed
impressions: each swipe is a **labeled point in embedding space** — this is active
learning, and the banded deck (30% twins / 40% same-vibe / 30% probes) is already an
information-gain design. The verdict machinery (`computeChallengeVerdict`) squeezes it
properly: cos²-weighted approval, yes-vs-no centroid delta, dwell-max favorite.

What to build on it (mostly wiring, not new ML):

1. **Persist the guest's taste FOR THE GUEST** (today it's only mirrored to the
   sender's `connections`). On response, write the same seeds/negatives under the
   guest's anonId (the client already has one), and let signup claim it — instant warm
   start, and the challenge becomes our primary user-acquisition loop with a
   ready-made taste profile on day zero.
2. **Seed the TasteObject deterministically:** `longTermClusters` ← yes-swiped item
   embeddings (already in the index — the seeds are pin keys); `negativeCentroid` ←
   no-swipes (weight fast, instant no's harder than hesitant no's via
   `swipe_decision_time`/`dwellMs`); price prior ← verdict `priceBand`; facet priors ←
   genderPref/birthday.
3. **Their first feed:** retrieve per yes-cluster, exclude deck items, higher
   exploration dose than normal (Thompson-style over the retrieved set) because 14
   points can't cover taste — but *anchored* exploration: probes near the yes-clusters,
   not uniform.
4. **The reveal is the conversion moment:** they already get back
   `{topCategories, priceBand}`; follow with one turn-taking question ("want your taste
   board? add your birthday?") — the same conversational pattern the AI-adoption
   research validated (§2.4) — and each answer lands in `events`/`graph`.

### 9.2 Mode G — giver-entry (gift for a friend / pledge in a pool)

The cardinal rule: **the giver's own taste is not the relevance signal — the
recipient's is.** The giver contributes constraints (budget, deal prefs, occasion,
relationship) and intent. Two structural consequences:

- **Mode-tag interactions.** Everything browsed/saved while in gift mode should carry
  `data: {mode:"gift", recipientRef}` on the `/interactions` write (the API already
  accepts a `data` payload) so gift-mode behavior accrues to a **per-recipient taste
  object**, not the giver's personal one. Alibaba's ComiRec saw gift shopping emerge as
  its own interest cluster even unlabeled (§1.2) — we can label it at the source.
- **Rank against the recipient-signal ladder** — use the highest rung available:
  1. **Descriptor only** (relation, "for him/her", occasion, budget): retrieval =
     `knowledge` table dyad priors (Reddit-mined ranked ideas per recipient type) +
     trending/popular within budget. This is exactly what the adoption research
     prescribes for socially distant recipients (§2.4), and it's a table we already
     have that the feed never touches.
  2. **A soft profile exists** (they completed a challenge; `connections.seeds`):
     vector retrieval seeded by the recipient's yes-pins → serendipity band from Part 1
     §3(d) — twin-band veto vs. their yes-history, **except** `variantPicks`, which are
     explicit "buy this variant" candidates and should rank first, not be vetoed.
  3. **A photo** (share-extension capture of something the recipient posted): visual
     search whose query vector is **retained as a recipient seed** (gap G3), not a
     one-shot query.
  4. **No signal and stakes are high** → the product's move is not to guess better but
     to *acquire signal*: prompt "send them a swipe challenge" or run Maxi's
     turn-taking recipient interview. Route back to rung 2.
- **Presentation:** deadline-driven givers convert on a **shortlist with one hero
  pick** (recipients asking for one specific item beat lists in the explicitness
  research, §2.5-adjacent) — not an infinite feed. Low exploration: a giver session is
  the wrong place to probe; spend exploration budget in Mode R and organic feeds.
- **Pledges as signals:** a `CONTRIB` row is a revealed dyad edge (giver↔recipient),
  revealed budget (amount), and an occasion timestamp — write it into `graph` and the
  giver's recipient roster so the next occasion for that person starts at rung 1+ with
  a real budget prior.

### 9.3 The cold-start ladder (both modes)

Rule: **no session ends with zero seeds.** Every entry path must deposit a persisted
seed set under *some* identity (anonId suffices): organic → consult vibes →
`pickSeedPins`; challenge guest → deck swipes; giver → recipient descriptor + any
photo/challenge-derived seeds; pledger → dyad + budget. Deezer-style cluster priors
(§1.4) cover whatever remains: cluster onboarding profiles (vibes × budget × genderPref)
and let new users inherit their cluster's bandit posterior until they outgrow it.

## 10. Revised gap list (supersedes §5 ordering where they conflict)

| # | Gap | Fix | Mode served |
|---|---|---|---|
| G1 | Challenge guest's taste only persists for the **sender** | Also write seeds/negatives under the guest's anonId; claim on signup | R |
| G2 | Gift-mode browsing pollutes the giver's personal taste | `data:{mode,recipientRef}` on interactions; per-recipient taste objects (schema slots already exist: `Recipient.pinSeeds`, `connections.seeds`) | G |
| G3 | Visual-search query vectors are discarded | `packVector` (already exists for challenge seeds) → store on the user/recipient record as a seed | R+G |
| G4 | Hides never reach the server (deliberate privacy stance) | Keep raw hides local; consider uploading only the *aggregated* negative centroid (int8, like `GET /vectors`) so server retrieval can subtract it — or accept device-only negative ranking | R |
| G5 | `SwipeListStore` ("saw it, thought of you") is device-local | Server-sync it: it's a labeled (item × giver × intended-friend) gift-intent triple — training gold nothing else captures | G |
| G6 | Dwell/hesitation/decision-time collected but unused | Fold into taste weights (dwell-scaled impressions; instant-yes > hesitant-yes — verdict already uses dwell for `favoriteId`, extend to profile updates) | R+G |
| G7 | `knowledge` dyad priors absent from feed retrieval | Add as a giver-mode candidate source (rung 1) | G |
| G8 | Pledges not fed back into the graph/roster | CONTRIB → graph edge + recipient budget prior + occasion calendar | G |
| G9 | Single-timescale, single-centroid taste | Part 1 §3(a)/(c): split stable vs. last-7-days centroids, k≤4 clusters — now on-device (`TasteProfileStore` is the natural home) | all |
