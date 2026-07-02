# On-Device Recommendation — hybrid client/server serving

**Status:** Phase 1 implemented · **Date:** 2026-07-02

Instagram-style layered serving for Giftmaxxing: the server keeps the work only
a server can do (full-corpus retrieval), and everything *per-user* moves onto
the phone. Personalization gets faster and richer while AWS per-request cost
drops, because generic candidate pages become CDN-cacheable and per-tap Lambda
writes become batches.

## 1. Research: what iOS actually allows / what fits

Apple fully supports on-device ML — it is a first-party platform pillar, not a
gray area. The relevant options, evaluated for a feed-ranking workload:

| Tech | What it is | Verdict for ranking |
|---|---|---|
| **Accelerate / vDSP** | SIMD vector math (dot products, conversions) on CPU | **Chosen.** 1024-d cosine over a 150-item page ≈ microseconds; zero app-size cost; no model to ship |
| **Core ML** | Compiled models on ANE/GPU/CPU; supports *updatable* models (on-device training via `MLUpdateTask`) | Right home for a **learned** ranker later (Phase 2). Overkill for a linear scorer |
| **NaturalLanguage `NLEmbedding`/`NLContextualEmbedding`** | On-device text embeddings | Different vector space than our server index (Titan MM) — cannot kNN against it. Only useful for local-only text features |
| **Vision `VNGenerateImageFeaturePrintRequest`** | On-device image embeddings | Same space problem. Becomes useful if we re-embed the catalog with a shared open model (Phase 3, MobileCLIP) |
| **MLX (mlx-swift)** | Apple-silicon array framework, runs quantized LLMs on iPhone | Wrong tool for ranking (tens of MB + battery for no accuracy gain). Right tool later for a **local Maxi** chat fallback |

Constraints checked: app-size impact of our approach is ~0 (no bundled model);
the vector cache is capped at 4096 × ~1 KB ≈ **4 MB** disk/RAM; ranking is
sub-millisecond vDSP work per page, so battery/thermal impact is negligible.
Nothing here touches App Store policy — it's plain user-space compute.

## 2. The layered split (who does what now)

```
Layer 1  RETRIEVAL        server   byFeed GSI recency window / S3 Vectors kNN (full corpus)
Layer 2  INTEGRITY        device   seen-history de-dup + ContentQuality gate (port of quality.mjs)
Layer 3  CHEAP FEATURES   device   quality, social proof, facet match (weight-parity with scorePost)
Layer 4  PERSONALIZATION  device   taste vibes, price fit, author affinity, cosine(item, taste centroid)
Layer 5  SESSION RE-RANK  device   author/category diversity spacing, negative feedback, exploration
```

Implementation map:

| Piece | File |
|---|---|
| Quality gate (classifyPin port) | `Giftmaxxing/Services/Recommendation/ContentQuality.swift` |
| Facet/vibe extraction | `Giftmaxxing/Services/Recommendation/TasteSignals.swift` |
| Local user model (decayed aggregates, seen-set, seeds) | `Giftmaxxing/Services/Recommendation/TasteProfileStore.swift` |
| Vector cache + vDSP centroid/cosine/kNN | `Giftmaxxing/Services/Recommendation/VectorStore.swift` |
| Layered ranker | `Giftmaxxing/Services/Recommendation/OnDeviceRanker.swift` |
| Batched interaction uploads | `Giftmaxxing/Services/Recommendation/InteractionQueue.swift` |
| Orchestration (over-fetch 40 → serve 12-pages locally) | `Giftmaxxing/Services/FeedViewModel.swift` |
| Server: quantized vectors + batch writes | `infra/src/handler.mjs` (`GET /vectors`, `POST /interactions` batch) |
| Edge: long-TTL `/vectors` cache behavior | `infra/cloudfront.tf` (`api_vectors` policy, honors degraded `no-store`) |

## 3. Why this saves money (the mechanics)

The account's binding constraint is a **Lambda concurrency cap of 10**
(docs/backend-scaling-design.md) — every avoided invocation is direct headroom.

- **Generic, cacheable candidate pages.** The iOS feed no longer sends
  `userId`; personal de-dup (`userExcludeSet`, previously a DynamoDB Query per
  page) and personal scoring happen on-device. Identical request URLs mean
  CloudFront can absorb feed reads: N users share one origin hit instead of N.
  The iOS client now points at the CloudFront distribution
  (`d21osnvwewgoao.cloudfront.net`, measured 0.31s vs 2.5s direct) instead of
  raw API Gateway, so it also rides the uncapped App Runner origin.
- **3–4× fewer feed requests per session.** One 40-item fetch is re-ranked and
  served locally as ~3 UI pages of 12.
- **Batched writes.** Likes/saves/opens queue locally and flush as one
  `POST /interactions {items:[…]}` per ~10 events (BatchWrite ≤25/chunk),
  instead of one invocation per tap. Impressions never leave the device at all
  (they only exist for de-dup/decay — uploading them would buy DynamoDB writes
  for zero ranking gain).
- **Vector math relocated.** Taste centroid + cosine ranking (previously
  `getCentroid` + scoring inside the Lambda per request) run in vDSP against a
  local int8 cache. The server serves raw vectors once per key
  (`GET /vectors`, ~1 KB/vector), then that item's similarity is free forever.
- **Graceful degradation got better.** When the cost breaker sheds AI routes,
  `/vectors` returns empty and the device falls back to facet-only local
  ranking — personalization *survives* degraded mode now, because the taste
  profile and cached vectors are already on the phone.

## 4. Wire protocol additions (backward compatible)

- `GET /vectors?keys=a,b,c` (public, ≤60 keys) →
  `{ items: [{ key, dim, scale, data }] }` where `data` = base64 int8
  components of the unit-normalized Titan embedding, `value[i] = int8[i] × scale`.
  Healthy responses carry `cache-control: public, max-age=86400` (embeddings
  are immutable per key) and CloudFront holds them at the edge for a day;
  degraded/breaker responses are `no-store` so an empty payload never sticks.
- `POST /interactions` now also accepts `{ items: [{ userId, targetId, type,
  createdAt? }] }` (≤100, de-duplicated, chunked into BatchWrite of 25).
  The single-event shape is unchanged (web untouched).

## 5. Privacy posture (worth stating in the App Store notes)

The full behavioral stream (impressions, dwell-adjacent signals, hides) stays
on-device in `Application Support/Recommendation/`. Only the same explicit
signals the app already sent (like/save/open) are uploaded, just batched. An
anonymous stable id (`gm.anonUserId`) is used pre-signin.

## 6. Roadmap

- **Phase 2 — learned ranker.** Replace the hand-tuned Layer 3/4 weights with a
  small Core ML *updatable* model (logistic regression over the same features),
  trained on-device from the local event log (`MLUpdateTask`). Server ships
  weight priors; phones personalize privately.
- **Phase 3 — shared embedding space on-device.** Re-embed the catalog with
  MobileCLIP (Apple, ~40–80 MB) alongside Titan, ship image embedding
  on-device, and visual search stops paying a Bedrock invoke per query. Gate on
  catalog size/cost math.
- **Phase 4 — local Maxi fallback.** MLX-swift or Foundation Models framework
  for a small on-device gift-suggestion model when `/maxi` is degraded/paused.
- **Ingest-time classification.** `classifyPin` still runs per-request in the
  feed route; precomputing it at ingest would shave Lambda CPU further and is
  a prerequisite for fully static/cached candidate pages.

## 7. Deploy status (done 2026-07-02)

- ✅ `terraform apply` — `api_vectors` cache policy + `/vectors` behavior on
  distribution `E2DQDSCTT58OV5`; Lambdas updated (api/breaker/reminders).
- ✅ App Runner `giftmaxxing-dev-api` image rebuilt + `start-deployment` (×2,
  second pass shortens empty-`/vectors` TTL to 300s) — RUNNING.
- ✅ Verified live: `/vectors` returns dim-1024 int8 vectors (~1.4 KB each),
  `max-age=86400`, CloudFront `Miss` → `Hit`; batch `POST /interactions`
  writes + de-dupes (3 sent → 2 written) with admin token.
- ⚠️ `POST /interactions` requires auth (Clerk JWT / admin token). The iOS
  client doesn't send a Clerk token yet, so anon uploads 401 (pre-existing;
  events stay queued on-device). Local personalization is unaffected.
- NOTE: the canonical terraform state now lives in THIS repo
  (`infra/terraform.tfstate`, gitignored), consolidated from the old
  `~/Downloads/Giftmaxing/infra` working copy — run all future plans/applies
  from here.

## 8. Verification

- `node --check infra/src/handler.mjs` — passes.
- `terraform fmt -check infra/cloudfront.tf` — passes (full `validate` needs
  `terraform init`, providers not installed locally).
- Swift: `swiftc -typecheck` over Models + Services + Recommendation — passes.
- int8 quantization roundtrip: cosine(original, roundtripped) = 0.999993 at
  1,368 B/vector (verified with a 1024-d random vector).
- iOS: `xcodegen generate && xcodebuild -project Giftmaxxing.xcodeproj -scheme Giftmaxxing -destination 'platform=iOS Simulator,name=iPhone 16' build`
- Manual: fresh install → scroll (impressions recorded) → like 3+ cozy items →
  pull-to-refresh → feed visibly re-orders toward cozy/home items and shows
  "Matches your cozy taste" reasons; Charles/proxy shows one `/interactions`
  batch per ~10 taps and `/feed` URLs with no `userId`.
