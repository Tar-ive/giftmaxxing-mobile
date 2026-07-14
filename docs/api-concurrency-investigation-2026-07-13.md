# API concurrency / App Runner investigation (2026-07-13)

Investigation after PR #36 AWS apply + reports of slow iOS feed / login / swipe
pagination. **No sizing or concurrency knobs were changed** — findings are for a
team discussion. Draft GitHub issue bodies live in
`docs/github-issue-drafts/` (this agent token cannot `gh issue create` on the
private repo).

## Executive summary

1. **Mobile does not hit the API Lambda today.** iOS and web both call
   CloudFront (`d21osnvwewgoao.cloudfront.net`), whose origin is **App Runner**.
   API Gateway / Lambda get single-digit–tens of requests per day.
2. **PR #34’s downsize rationale is incorrect in code comments.** It claims App
   Runner is “website only; mobile uses Lambda.” Both clients use CloudFront →
   App Runner. Downsizing App Runner (1 vCPU / 2 GB → **0.25 vCPU / 0.5 GB**)
   therefore affects mobile latency, not “just the website.”
3. **Lambda reserved concurrency = 100** is a real flood guard for the *legacy*
   path (Jun 27–28 hit 269 concurrent / ~1.6M throttles), but it is **not** what
   currently throttles the feed — almost no mobile traffic reaches Lambda.
4. Observed App Runner CPU/memory util is still low after the downsize; tail
   `RequestLatency` max still reaches **0.4–2.6 s**. First uncached `/feed` ≈
   **1.0 s**; CloudFront HIT ≈ **40 ms**. Cursor pagination likely re-pays
   origin cost.

## Live settings (verified 2026-07-13)

| Knob | Value |
|---|---|
| Lambda `giftmaxxing-dev-api` reserved concurrency | **100** |
| Account ConcurrentExecutions quota | **1000** (900 unreserved) |
| App Runner CPU / memory | **256 (0.25 vCPU) / 512 MB** |
| App Runner autoscaling | maxConcurrency 100 × maxSize 5 = 500 ceiling; minSize 1 |
| CloudFront API | `https://d21osnvwewgoao.cloudfront.net` → App Runner |
| API Gateway | `https://tvyu8gqmki.execute-api.us-east-1.amazonaws.com` → Lambda |

## Traffic evidence (approx.)

| Path | Recent volume |
|---|---|
| App Runner `Requests` | tens–hundreds / hour when in use (peaks ~269–295 / hour) |
| API Gateway `Count` | ~1–19 / day |
| Lambda `Invocations` | tens / day; `ConcurrentExecutions` max ≈ 1 |
| Lambda `Throttles` since cutover | 0 (flood day Jun 27: **1,594,647**) |

## Client routing (source of truth)

- iOS: `Giftmaxxing/Services/APIClient.swift` → CloudFront URL
- Web: `web/.env.example` `NEXT_PUBLIC_API_URL` → same CloudFront URL
- Terraform: `infra/cloudfront.tf` origin = `aws_apprunner_service.api.service_url`
- Misleading comment: `infra/apprunner.tf` instance_configuration block (PR #34)

Cached CF paths: `/feed`, `/pins`, `/recommendations`, `/ideas`, `/vectors`.
Everything else (auth/session, interactions, Maxi, visual-search, personalized
queries) is live App Runner.

## PR #36 AWS runbook status (this agent)

| Step | Result |
|---|---|
| `npm test` in `infra/src` | 11/11 pass |
| `terraform apply` (Lambda api/breaker/reminders code) | 0 add / 3 change / 0 destroy |
| Docker build + ECR push + App Runner `start-deployment` | SUCCEEDED; `/healthz` 200 |
| `clean:posts` | deleted **5** `non-gift` auto-part rows (Dorman / ACDelco / …) |
| `prune-vectors --apply` | pruned **73** orphan/bad vectors |
| `enrich:images` | running; **eBay + Etsy return HTTP 403** from this egress IP — galleries for those domains will not backfill until crawler/egress is fixed (see issue draft #2) |

## Questions for the team (do not auto-resolve)

1. Canonical mobile backend: keep CF→App Runner, or move mobile to Lambda?
2. App Runner size: stay 0.25/0.5 for cost, restore 1/2, or pick a middle?
3. Lambda reserved=100: keep as legacy flood guard, raise, or −1?
4. Feed pagination / cache-HIT design so swipe pages don’t wait on cold origin?
5. Need p95 latency dashboards split by CF HIT vs MISS vs App Runner?

## Related

- PR #34 — App Runner downsize + Lambda reserved concurrency
- PR #36 — feed polish + this runbook
- `docs/backend-scaling-design.md` — longer-term scaling design
- Issue drafts: `docs/github-issue-drafts/`
