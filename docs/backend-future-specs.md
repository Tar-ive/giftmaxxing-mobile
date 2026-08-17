# Backend specs that are not built yet

> Moved out of `CLOUD.md` on 2026-08-17, verbatim. Everything here is a DESIGN, not a
> deployed system: native ads, visual-search affiliate enrichment, the gift knowledge
> graph server halves, and the clustering/pool serving layer. Check `CLOUD.md` for what
> actually exists before building against any of it.

## 5. Native (seamless) ads — Pinterest-style

### 5.1 What makes Pinterest ads feel organic (the pattern to copy)
- **Same card, same grid.** A Promoted Pin uses the **exact same component** as an organic Pin — same image-first layout, aspect ratios, hover/tap behavior. No banner, no separate "ad slot" chrome, no different background.
- **Minimal disclosure.** The only tell is a small, low-contrast **"Promoted" / "Promoted by {advertiser}"** label (muted text near the attribution), plus a `…` menu with **"Why am I seeing this ad?"** / hide. No loud "AD" badge.
- **Relevance-placed.** Ads are interleaved into the organic feed at intervals and chosen by the **same relevance/taste model**, so the sponsored item matches the surrounding vibe — that's *why* it's hard to distinguish.
- **Same interactions.** Save / click / comment / hide work identically; hiding feeds "fewer ads like this." CTA ("Visit"/"Shop") appears on closeup/hover, not as an intrusive grid button.

### 5.2 Giftmaxxing implementation
- Extend `Post` (`web/lib/social.ts`): `sponsored?: boolean; advertiser?: string; cta?: "Shop" | "Visit"`.
- Render in `PostCard` (`web/components/app/post-card.tsx`) using the **same card**; in the header slot where `rec` shows `Suggested · {reason}`, show a muted **`Sponsored`** (+ optional `· {advertiser}`) and a `…` → "Why am I seeing this?". Reuse the existing product chip as the subtle CTA.
- **Interleave** sponsored items in `recommendPage()` at a fixed cadence (e.g. 1 in every 5–6 posts) **but rank them by the same taste centroid** so they match the user's vibe. Apply a frequency cap and respect "hide."

---

## 6. Visual search — "Google Lens for gifts" (FUTURE, indexed for later agents)

> **Status: future / not built yet.** Documented + indexed here so a later agent can pick it up.

**Goal.** User uploads/snaps a photo → we return **visually similar, buyable products with Amazon/Walmart affiliate links** (à la Google Lens).

**Pipeline (reuses everything above):**
1. `POST /visual-search` (multipart image) → Lambda.
2. Embed the query image with the **same** Titan Multimodal model → query vector.
3. **kNN** against the product/affiliate catalog vectors (Phase 1 brute-force → Phase 2 S3 Vectors).
4. Enrich top-k with **affiliate links** and return.

**Affiliate sources (need approval + secrets):**
- **Amazon Associates** — Product Advertising API (PA-API 5.0) for product data; append the associate tag to links. Keys: `AMAZON_ASSOCIATES_*`.
- **Walmart** — Walmart Affiliate Program (Impact) + Walmart Affiliate/IO API. Keys: `WALMART_AFFILIATE_*`.
- Never hard-code keys; store in env/secrets manager.

**Also enables:** "shop this pin" — turn a Pinterest idea image into buyable lookalikes via the same kNN.

---


## 14. Gift knowledge graph — server-side spec (NOT buildable from this repo / Terraform)

> **Status: spec only.** The client half shipped Jul 2026 (`GiftGraphRanker.swift`, see §8).
> Everything below is Lambda/DynamoDB **application code + data**, not infrastructure —
> Terraform can't express it, and the pieces need production interaction data and a
> Lambda deploy (standing runbook in §8). Written for the infra/backend agent.

### 14.1 `GET /recommendations?mode=surprise` — true multi-hop random walk

The client's `surpriseWalk()` approximates "outside the cluster" over ONE feed page
(60 candidates). The real version walks the vector graph server-side:

1. Seed = the user's taste centroid (existing `get-vectors` + average path in `handler.mjs`).
2. Hop 1: `query-vectors(centroid, topK=50)`; **sample from the middle band**
   (ranks ~20–50, cosine ≈ 0.35–0.55) instead of the head — adjacent-but-not-predicted.
3. Hop 2..N (2–3 hops total): re-query from the sampled item's vector, sample the
   middle band again. Each hop decays relevance and raises novelty (the classic
   knowledge-graph random-walk-with-restart, restart prob ~0.3 back to the centroid).
4. Filter through `classifyPin` (feed-eligible only), de-dup categories, return ~14 items
   with `source:"surprise"` and per-item `hops` so the client can badge "a stretch, but…".

S3 Vectors has no walk primitive — it's all Lambda-side sampling over repeated
`query-vectors` calls (3–4 queries per request; pennies at our scale).

### 14.2 Per-relationship-cohort social proof ("trusted curators")

The client uses app-wide likes as a placeholder. The real feature: "people shopping
for a *partner* saved this" — proof from the giver's OWN cohort, and proof from
high-Thoughtfulness curators specifically:

- **Write:** interactions already flow to the `interactions` table; add optional
  `relationship` context to the batched payload when the action happens inside a Gift
  Board that has one (client already knows it — one field in `InteractionQueue`).
- **Aggregate:** on write (or hourly), maintain `proof#<postId>` rows:
  `{ byRelationship: {partner: n, parent: n, …}, byCuratorTier: {high: n, all: n} }`.
  Curator tier = the acting user's Thoughtfulness Points band (client syncs the
  points total; treat as advisory).
- **Read:** `/feed` + `/recommendations` join the proof row and emit
  `socialProof: { relationship, count }`; the client's `W.socialProof` term consumes
  it instead of raw likes when present.

### 14.3 Persist the graph edges (gNode/gEdge)

`handler.mjs` already writes graph rows for challenges/connections. Extend so the
recipient graph survives device wipes and powers server ranking:

- **Board → recipient edge:** when a board is shared (`POST /challenges`), persist
  `gEdge{ giver → recipient(name-hash), type:"gifts_for", relationship, occasion }`.
- **Feedback edges:** each guest response already stores per-item yes/no; also write
  `gEdge{ recipient → postId, type:"loved"|"passed" }` so any future device can
  rebuild `feedbackSeedIds` server-side instead of from local challenge caches.
- **Recipient interests:** add an optional `interests:[…]` field to
  `POST /challenges/{id}/response` (guests can tag what they're into after swiping —
  the "Relationship Manager Q&A") → stored on the connection, surfaced in
  `GET /connections` (`vibes` today only carries deck-derived signals).

### 14.4 Runbook

1. Implement 14.1–14.3 in `infra/src/handler.mjs` (+ tests in `infra/src`), deploy the
   Lambda per the standing runbook in §8.
2. No new Terraform: same DynamoDB table (new `proof#`/`gEdge` item types), same
   S3 Vectors index, same API routes (one new query param, one new response field).
3. Client follow-up (iOS agent): point `SwipeViewModel.loadSurprise()` at
   `mode=surprise` when the deploy lands (keep the on-device walk as offline fallback),
   and consume `socialProof` in `OnDeviceRanker`.

---

## 15. Recommendation scale-up — pools, clustering, full-catalog embeddings

> **Status:** client + backfill driver shipped Jul 2026; the SageMaker/clustering
> halves are spec-only (need AWS + production interaction data). For the
> infra/ML agent.

### 15.1 What already exists (don't rebuild)

- **`GET /recommendations?userId=&limit=`** is LIVE and does exactly the
  "recommendation API" design: seeds = the user's own interaction rows
  (INTERACTIONS table) → taste centroid → S3 Vectors kNN → items sorted by
  score, `source:"vector"`. Cold start (no interactions) falls back to the
  facet scan (`source:"facet"`) automatically. It returns full item metadata,
  not just ids — the client needs no second DynamoDB read.
- **Client (Jul 2026):** the iOS Home feed is now recommendation-API-first —
  `FeedViewModel.fetchPersonalizedPicks()` calls `/recommendations?userId=`
  concurrently with the generic candidate page and weaves `source:"vector"`
  picks into slots 1/4/7/10; on cold start it contributes nothing and the
  generic page stands alone. The CloudFront-cacheable generic page remains the
  candidate backbone (cost model intact — one extra Lambda call per feed load,
  signed-in users only).
- **Tag-based pools, manual tier:** posts already carry `category` + vibe tags,
  and the client ships 12 curated "gift galleries" (`CuratedCollection`) that
  ARE the hand-made starter pools ("Tech Lover's Wishlist" = the tech pool).
  Onboarding personas map to vibes (`GiftingPrefs` → `consultVibes`) which bias
  candidate generation server-side today.

### 15.2 Full-catalog embeddings — Titan, NOT CLIP (backfill driver shipped)

~21.3k posts carry remote image URLs but only a fraction are in the vector
index. **Do not add a CLIP-on-SageMaker path for this:** CLIP embeds into a
*different* vector space — its vectors cannot be compared or fused with the
existing Titan Multimodal 1024-d index, so "generate CLIP embeddings and
compare with the existing vectors" doesn't work. The existing pipeline already
handles remote images (`embed.mjs` fetches `imageUrl` when there's no `s3Key`).

Runbook (AWS creds; ~$0.64 one-time on-demand, ~$0.32 batch):
1. `cd infra/ingest && npm run backfill:vectors` — scans POSTS, diffs against
   the index (`list-vectors`), reports missing-by-brand (top-20 first via
   `--brands top`), writes `backfill.manifest.json` (junk excluded via
   `feedEligible`).
2. `node embed.mjs --manifest backfill.manifest.json` — Titan MM → PutVectors,
   same index, same space. `--limit N` to stage; idempotent (re-put = upsert).
3. Verify: `/visual-search` now returns Shopify/gallery products; `GET
   /recommendations?userId=` covers the full catalog.

(CLIP on SageMaker is fine as a SEPARATE experiment index for offline eval —
never mixed into `pins`.)

### 15.3 User clustering (SageMaker notebook) + expert-seeded cold start

Goal: cluster users by swipe/like history; serve each cluster a shared gift
pool; seed brand-new users from "expert" (high-activity) users' pools.

- **Data:** INTERACTIONS table (userId, target, type) + challenge responses
  (CONNECTIONS.seeds = yes-swipes). Export to S3 via a one-off scan or DynamoDB
  → S3 export. Join targets to their Titan vectors (S3 Vectors `get-vectors`)
  so items are dense features, not ids.
- **Notebook (SageMaker, `infra/ml/` when created):** build user profiles =
  mean vector of liked items (same centroid math as prod); cluster with
  MiniBatchKMeans (k≈8–20, elbow/silhouette) or, once interactions are dense
  enough, implicit-feedback matrix factorization (`implicit` ALS) and cluster
  the user factors. Label clusters by their top categories/vibes → these ARE
  the "Tech Enthusiast"/"Fashionista" pools, learned instead of hand-set.
- **Pool generation:** per cluster, top-N items by (a) member engagement and
  (b) kNN around the cluster centroid — write as `pool#<clusterId>` rows in
  DynamoDB (CONFIG or POSTS table, item type `pool`): `{ clusterId, label,
  itemIds[', updatedAt }`. Small, hot, cache-friendly.
- **Serving (Lambda, no new infra):** `GET /recommendations` gains a cheap
  pre-step — look up the user's `clusterId` (stored on their USERS row by the
  notebook's assignment export), fetch `pool#<clusterId>`, and blend pool items
  into the candidate set before the personal-centroid kNN re-ranks. New users
  with zero interactions get their onboarding persona mapped to the nearest
  cluster (persona vibes → cluster label match) — the "expert seeds beginner"
  cold-start accelerator.
- **Refresh:** re-run the notebook weekly (EventBridge → SageMaker Processing
  job once it stabilizes); assignments + pools are plain DynamoDB writes.

### 15.4 Order of operations

1. **15.2 backfill first** — clustering quality depends on item vectors
   existing for what users actually swiped on.
2. Then export interactions → notebook → first k-means pools.
3. Lambda pool blend + USERS.clusterId assignment.
4. Revisit matrix factorization once weekly actives × interactions justify it.

---

