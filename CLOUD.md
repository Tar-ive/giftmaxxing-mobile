# CLOUD.md — Giftmaxxing backend architecture

> **What this file is.** The current state of the AWS backend that serves the iOS app: what runs,
> what stores what, and which model does the ranking. It describes *what exists today*, not what we
> plan to build.
>
> **History and specs live elsewhere** — keep them there, so this file stays loadable:
> - `docs/backend-changelog.md` — every shipped slice, why it was built, what it replaced
> - `docs/backend-future-specs.md` — designed but NOT built (native ads, knowledge-graph server halves, clustering pools)
> - `docs/ml-mtl-stack.md` — full detail on the MTL model: training, features, serving, runbook
>
> **Account:** `445056752928` · **Region:** `us-east-1` · **Terraform:** `infra/`, S3 backend
> (`giftmaxxing-tfstate-445056752928`), Terraform ≥ 1.15.6.

## 1. Request path

```
iOS app ─┐
         ├─▶ CloudFront ─▶ App Runner (container, infra/apprunner.tf) ─┐
web app ─┘                                                            ├─▶ same Node handler
                └─▶ API Gateway HTTP API ─▶ Lambda giftmaxxing-dev-api ┘
```

Both the container and the Lambda run the code in `infra/src/`. **A deploy means both**: `terraform
apply` for the Lambda, plus an ECR build/push and `apprunner start-deployment` for the container.
Shipping only one leaves the two serving different code — a real bug we have hit.

API base (direct): `https://tvyu8gqmki.execute-api.us-east-1.amazonaws.com`
The app reads it from `NEXT_PUBLIC_API_URL` (web) / `APIClient` base (iOS).

## 2. Lambda functions

| Function | Job |
|---|---|
| `giftmaxxing-dev-api` | Everything in §3. The monolith handler. |
| `giftmaxxing-dev-breaker` | Cost kill-switch (`infra/killswitch.tf`) |
| `giftmaxxing-dev-reminders` | Scheduled gift-date reminders → push |
| `giftmaxxing-dev-taste-profile-stream` | DynamoDB stream → taste profile rollups |
| `giftmaxxing-dev-ugc-ingest` / `-ugc-results` | Rekognition safety review for user media. **Legacy** — the iOS app no longer posts; these still serve historical rows. |

## 3. The API surface

`infra/src/handler.mjs` routes; the rest of `infra/src/` are its modules.

**Feed and recommendations** — `GET /feed` (facet ranker + diversity spacing, CloudFront-cached by
URL with a `d=<UTC-day>` bucket and an `r=` millis buster on pull-to-refresh) · `GET
/recommendations` (taste centroid → S3 Vectors kNN; `?rank=full` adds the MTL re-rank) · `POST
/v2/recommendations` (recommender-v2 mixer) · `GET /v2/feed-taxonomy` · `GET /ideas` · `GET
/bundles` · `GET /galleries/{id}` · `GET /curated/…`

**Search and vectors** — `POST /visual-search` (image → Titan embedding → kNN → retailer-biased
re-rank) · `GET /vectors` · `GET /pins`

**Maxi** — `POST /maxi` (tool-calling workflow: gift briefs, `find_gifts` over the vector path,
cart) · `GET /maxi/history` · `POST /packaging`

**Identity and people** — `POST /login` · `POST /auth/session` · `GET|PUT /me` · `DELETE /account`
(App Store 5.1.1(v) self-service deletion) · `GET /people` · `/friends*` · `/dms*` · `/connections*`
· `/circles*` · `/challenges*` · `/pools*` · `/board-shares`

**Events and telemetry** — `/events*` · `POST /interactions` · `POST /mobile/interactions/batch` ·
`POST /v2/events/batch` · `/mobile/analytics*` · `POST /mobile/device` · `GET /mobile/sync`

**Ops** — `GET /healthz` · `POST /seed` (ingest scripts write catalog rows through this)

### Handler modules

`recommender-v2.mjs` + `recommender-model.mjs` + `recommender-policies.mjs` (the v2 mixer) ·
`quality.mjs` (`classifyPin`, the non-gift / feed-eligibility gate) · `feed-diversity.mjs` (brand and
category spacing) · `feed-taxonomy.mjs` · `featured-feed.mjs` · `catalog-v2.mjs` · `maxi-tools.mjs`
· `packaging.mjs` · `friends-routes.mjs` (the single privacy chokepoint — `publicCard`) ·
`mobile-routes.mjs` · `analytics-routes.mjs` · `birthday-freebies.mjs` · `push.mjs` ·
`api-signature.mjs` · `breaker.mjs`

Tests: `npm --prefix infra/src test` (node:test). Run before any deploy.

## 4. Data stores

**DynamoDB** (on-demand, `infra/dynamodb.tf`) — 18 tables:
`users` · `posts` · `interactions` · `taste_profiles` · `analytics` · `events` · `connections` ·
`challenges` · `friends` · `pools` · `graph` · `knowledge` · `config` · `catalog_entities` ·
`catalog_edges` · `devices` · `ugc_reports`

Notable shapes: `config` holds `gallery#<id>` and `bundles#<recipient>` rows built by
`infra/ingest/build-shelves.mjs`; `graph` holds `BRIEF#` rows (Maxi gift briefs) and gift-graph
edges; `knowledge` holds the Reddit-mined gift lexicon.

**S3** — `giftmaxxing-dev-media` (images + thumbnails) · `giftmaxxing-dev-ml` (model artifacts and
training datasets) · the Terraform state bucket.

**S3 Vectors** — bucket `giftmaxxing-dev-vectors`, index `pins`: 1024-d, cosine, float32.
Non-filterable metadata: title, pinUrl, imageUrl, s3Key, sourceUser. This is the canonical vector
store; it is script-managed (`infra/ingest/s3vectors-setup.mjs`), not a Terraform resource.

## 5. Models

| Model | Where | Used for |
|---|---|---|
| Titan Multimodal Embeddings G1 (`amazon.titan-embed-image-v1`) | Bedrock | Every vector in the index: image+text → 1024-d. Text and image share the space, which is what makes text→image and image→image the same query. |
| Claude Haiku 4.5 | Bedrock | Maxi's shopping tier |
| Nova (Lite/Pro) | Bedrock | Maxi's base tier, packaging plans |
| Stability (us-west-2) | Bedrock | Packaging images (Nova Canvas was retired mid-flight) |
| MTL value model | SageMaker serverless endpoint | Re-ranks `/recommendations?rank=full`. `Score = 2·P_Time + 5·P_Custom + 1·P_Buy`. Dark unless `MTL_ENDPOINT` is set; any error or timeout soft-falls back to cosine order. Detail: `docs/ml-mtl-stack.md`. |

## 6. Ranking, end to end

1. **Candidates** — `GET /feed` scans POSTS, applies `classifyPin` quality gates, then
   `feed-diversity` spacing (brand ≤2 in a row, category ≤2 in a row).
2. **Personalization** — `GET /recommendations?userId=` reads that user's INTERACTIONS, averages
   their item vectors into a taste centroid, and runs a kNN against S3 Vectors.
3. **Re-rank** — `?rank=full` sends candidates to the MTL endpoint. The iOS client calls the fast
   path first, paints, then refines below the fold.
4. **On device** — `OnDeviceRanker` re-scores the served page against the local taste profile, and
   treats the server's `feedEligible` as a veto, so a new quality rule reaches users without a
   Lambda deploy.

## 7. Ingest (`infra/ingest/`)

Run with `set -a; source ../../.env; set +a` or an active `AWS_PROFILE`.

`pinterest-rss.mjs` (public RSS → S3; the v5 API rejects our app's consumer type) · `embed.mjs`
(image + title → Titan → PutVectors) · `ingest-shopify.mjs` (22 stores' public `/products.json`;
fetch from the internal `*.myshopify.com` host — headless storefronts block the custom domain) ·
`ingest-catalog.mjs` (curated products + gift-able services) · `build-shelves.mjs` (themed galleries
and Reddit bundles → CONFIG) · `enrich-images.mjs` (gallery crawl; eBay/Etsy need their official
APIs, they 403 plain fetches) · `backfill-vectors.mjs` · `prune-vectors.mjs` · `clean-posts.mjs`

**In a proxied container, run node with `NODE_USE_ENV_PROXY=1`** — Node's fetch ignores
`HTTPS_PROXY` and the egress 429s.

## 8. Costs

Embedding is a sub-dollar one-time cost: Titan multimodal is **$0.00006/image** on demand
(−50% batch), so ~21k catalog images ≈ **$0.64**. S3 media is pennies per month, DynamoDB
on-demand is pennies, Lambda is inside the free tier, and the SageMaker serverless endpoint scales
to zero. The only line items that could surprise us are OpenSearch Serverless (~$350/mo minimum —
**not used**, and shouldn't be until ANN latency at scale demands it) and Bedrock Provisioned
Throughput (~$9.38/hr — never for this workload). `infra/budgets.tf` and the breaker Lambda are the
guardrails.

## 9. Environment

```
BEDROCK_EMBED_MODEL_ID=amazon.titan-embed-image-v1
MEDIA_BUCKET=giftmaxxing-dev-media
VECTOR_BUCKET=giftmaxxing-dev-vectors
VECTOR_INDEX=pins
MTL_ENDPOINT=                 # unset = MTL re-rank stays dark
PACKAGING_IMAGES=0            # 1 needs a Bedrock image-model access grant
PINTEREST_RSS_USERS=etsy,marthastewart,uncommongoods
EBAY_CLIENT_ID= / EBAY_CLIENT_SECRET= / ETSY_API_KEY=    # free keysets, for gallery enrichment
AMAZON_ASSOCIATES_* / WALMART_AFFILIATE_*                # affiliate enrich (future)
```

Secrets live in `.env` (gitignored) locally and Secrets Manager in AWS. Never commit them.

## 10. Known gaps

- **The UGC pipeline is legacy.** The app can't post any more and the client filters `source:"ugc"`
  out of the feed, but `/ugc*` routes and the two Rekognition Lambdas still exist. Retiring them is
  unstarted.
- **eBay and Etsy galleries** stay sparse until the official-API path in `enrich-images.mjs` is
  wired; plain crawls get 403.
- **GitHub Actions is dead** (billing), so nothing here is deployed by CI today — see `DEPLOY.md`.
