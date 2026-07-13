# Draft GitHub issues (paste into GitHub — agent token lacks `issues: write`)

The cloud agent that ran the 2026-07-13 investigation could merge/read via the
repo token but **could not** `gh issue create` (`Resource not accessible by
integration`). Please file these manually (or grant the agent `issues` scope).

Full write-up: [`../api-concurrency-investigation-2026-07-13.md`](../api-concurrency-investigation-2026-07-13.md)

---

## Issue A — Team discussion: Lambda reserved concurrency vs App Runner downsize

**Title:** Team discussion: Lambda reserved concurrency (100) vs App Runner downsize — slow feed/login?

**Labels:** (suggested) `infra`, `discussion`, `performance`

**Body:**

```markdown
## Context

Came out of investigating slow iOS feed/login/swipe pagination after PR #34 and while applying PR #36's AWS runbook.

**Please treat this as a team discussion — do not silently re-tune sizes/caps without agreement.**

Full notes: `docs/api-concurrency-investigation-2026-07-13.md`

## What we believe happened historically

1. **Jun 27–28 2026 flood on the API Lambda** — peak ConcurrentExecutions ≈ **269**, ~**1.6M Throttles** that day.
2. **App Runner introduced (Jun 28)** so user-facing traffic could leave the Lambda concurrency funnel.
3. **PR #34 (Jul 13)** then:
   - App Runner **1 vCPU / 2 GB → 0.25 vCPU / 0.5 GB**
   - API Lambda `reserved_concurrent_executions` **−1 → 100**

Account ConcurrentExecutions quota is now **1000** (was 10 when `docs/backend-scaling-design.md` was written).

## Critical routing fact (PR #34 comment is wrong)

PR #34 / `infra/apprunner.tf` says App Runner is “website only; mobile uses the Lambda HTTP API.”

**Production clients today:**

| Client | Base URL | Origin |
|---|---|---|
| iOS `APIClient.swift` | `https://d21osnvwewgoao.cloudfront.net` | CloudFront → **App Runner** |
| Web `NEXT_PUBLIC_API_URL` | same | CloudFront → **App Runner** |
| Raw API Gateway | `…execute-api…` | Lambda (barely used) |

### Live traffic (Jul 11–13)

- API Gateway: ~1–19 req/day
- Lambda ConcurrentExecutions max ≈ 1
- App Runner: tens–hundreds req/hour when in use

So reserved-concurrency=100 is **not** what mobile hits for feed/login. **App Runner size is.**

## Current live settings

| Knob | Value |
|---|---|
| Lambda reserved concurrency | **100** |
| App Runner | **0.25 vCPU / 512 MB**, min 1 / max 5, maxConcurrency 100 |
| App Runner CPU util | ~0.5–7% (spike ~14%) |
| App Runner RequestLatency | avg ~50–100 ms; **max 0.4–2.6 s** |
| Uncached `/feed` via CF | ≈ **1.0 s**; CF HIT ≈ **40 ms** |

## Hypotheses for slow feed / swipe

1. Cursor / personalized feed pages miss edge cache → re-pay origin every page.
2. Single-instance Node on 0.25 vCPU can stretch tail latency under bursts even when average CPU looks idle.
3. Lambda reserved=100 would throttle again **if** we fail back to API Gateway (flood peak was 269).

## Questions (do not auto-resolve)

1. Canonical mobile backend — keep CF→App Runner, or move mobile to Lambda?
2. App Runner size — stay 0.25/0.5, restore 1/2, or middle ground?
3. Lambda reserved=100 — keep as legacy flood guard, raise, or −1?
4. Feed pagination caching so swipe doesn’t wait on cold origin?
5. p95 latency dashboards split by CF HIT vs MISS vs App Runner?

## What we did NOT change

No sizing / concurrency knobs were reverted or raised.

## Related

- PR #34, PR #36
- `infra/apprunner.tf`, `infra/lambda.tf`, `infra/cloudfront.tf`
- `Giftmaxxing/Services/APIClient.swift`
- `docs/backend-scaling-design.md`
```

---

## Issue B — enrich-images: eBay/Etsy HTTP 403 from cloud egress

**Title:** `enrich-images.mjs` gets HTTP 403 from eBay/Etsy (gallery backfill blocked)

**Labels:** (suggested) `infra`, `data-quality`

**Body:**

```markdown
## Problem

PR #36 added `infra/ingest/enrich-images.mjs` to backfill `product.images` for the iOS carousel. From the Cursor cloud / AWS SSO egress used on 2026-07-13:

| Host | Result |
|---|---|
| `ebay.com` | **HTTP 403** |
| `etsy.com` | **HTTP 403** |
| `amazon.com` | 200 |
| `uncommongoods.com` | 200 |

Catalog mix is heavy on eBay (~196) + Etsy (~432) of ~1847 posts, so the “visible wins” path in the runbook (`--only-domain ebay.com,etsy.com`) currently yields almost no galleries.

UA already spoofs Chrome (`enrich-images.mjs`); still blocked — likely bot/IP reputation, not a missing header.

## Impact

- `/feed` `product.images` stays empty for most shoppable pins → iOS carousel falls back to single image.
- Full-catalog enrich is running for domains that allow fetch; eBay/Etsy need a different strategy.

## Ideas for the team (not implemented)

1. Run enrich from a residential / different egress (or locally).
2. Use retailer APIs / affiliate image feeds instead of HTML scrape.
3. Capture gallery at ingest time (Pinterest pin already often has multiple images).
4. Accept single-image for blocked domains; prioritize Amazon/Shopify-style stores.

## Related

- PR #36
- `docs/api-concurrency-investigation-2026-07-13.md`
- CLOUD.md §8 feed-polish runbook step 3
```

---

## Issue C — Fix misleading App Runner “mobile uses Lambda” comment

**Title:** Docs/comments claim mobile uses Lambda; clients actually hit CloudFront→App Runner

**Labels:** (suggested) `infra`, `docs`, `good-first-issue`

**Body:**

```markdown
## Problem

`infra/apprunner.tf` (instance_configuration comment from PR #34) says:

> App Runner serves only the (low-traffic) website; the mobile app uses the Lambda HTTP API.

That is false for production:

- iOS `APIClient.swift` → `https://d21osnvwewgoao.cloudfront.net`
- CloudFront origin → App Runner (`infra/cloudfront.tf`)

This misconception is what made the App Runner downsize look “safe for mobile.”

## Proposed fix (small, after Issue A decision)

1. Rewrite the comment to match reality (or whatever the team decides is canonical).
2. Optionally add a one-liner to `infra/README.md` / `DEPLOY-ANYWHERE.md`: “Mobile + web → CloudFront → App Runner; Lambda/API Gateway is fallback/legacy.”

Do **not** change sizes in the same PR — that’s Issue A.
```
