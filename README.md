<h1 align="center">Giftmaxxing 🎁</h1>

<p align="center">
  <b>Gift-giving is a craft.</b><br/>
  Giftmaxxing learns the taste of the people you love, remembers every date that matters, and turns
  <i>"I have no idea what to get them"</i> into the right gift.
</p>

<p align="center">
  <a href="https://apps.apple.com/app/id6788124639"><b>App Store</b></a> &nbsp;·&nbsp;
  <a href="https://giftmaxxing-web.vercel.app"><b>Web</b></a> &nbsp;·&nbsp;
  <a href="AGENTS.md"><b>Start here if you're an agent</b></a>
</p>

---

## What ships where

| Surface | Status |
|---|---|
| **iOS app** — the product | App Store **1.1.2** live · TestFlight **build 146** (1.1.3) |
| **Backend** — AWS, `us-east-1` | Live behind CloudFront + App Runner + API Gateway |
| **Web** — Next.js on Vercel | Secondary surface; auto-deploys from `main` |

## Repo map

| Path | What's in it |
|---|---|
| `Giftmaxxing/` | The iOS app: views, stores, app state |
| `Packages/GiftmaxxingKit/` | Local Swift package — `GiftmaxxingCore` (models), `GiftmaxxingRecommendation` (on-device ranking). **Never imports the app target.** |
| `GiftmaxxingShare/` | Share extension: any app's share sheet → visual search |
| `GiftmaxxingTests/` | App-target tests (56). Package tests live with the package (41). |
| `infra/` | Terraform, the Lambda/App Runner handler (`src/`), ingest scripts (`ingest/`), ML (`ml/`) |
| `web/` | Next.js app |
| `docs/` | Everything below |

## Run it

```bash
# iOS — the .xcodeproj is generated, so this comes first, always
xcodegen generate && open Giftmaxxing.xcodeproj

# fast test loop (~2s)
swift test --package-path Packages/GiftmaxxingKit

# web — no secrets needed; falls back to bundled data when the API is unreachable
npm --prefix web install && npm --prefix web run dev

# backend tests
npm --prefix infra/src test
```

## The four files that govern this repo

| File | What it decides |
|---|---|
| **[AGENTS.md](AGENTS.md)** | How agents work here: build/test commands, module and design-token rules, no-auto-merge, how these docs are maintained. Canonical — `CLAUDE.md` just points at it. |
| **[DESIGN.md](DESIGN.md)** | The iOS design system: tokens, the 8-palette theming system, components, motion. Read before any UI change. |
| **[CLOUD.md](CLOUD.md)** | Current backend architecture: request path, API surface, data stores, models, ranking. |
| **[DEPLOY.md](DEPLOY.md)** | How each surface ships. CI is down, so releases are local — the runbook is here. |

## Documentation index

**Architecture & product**
[architecture](docs/architecture.md) ·
[ios-information-architecture](docs/ios-information-architecture.md) ·
[product-feature-set](docs/product-feature-set.md) ·
[user-stories](docs/user-stories.md) ·
[intentional-gifting](docs/intentional-gifting.md) ·
[guest-boundary](docs/guest-boundary.md)

**Recommendations & ML**
[recommender-v2](docs/recommender-v2.md) ·
[recommender-evaluation](docs/recommender-evaluation.md) ·
[on-device-reranking](docs/on-device-reranking.md) ·
[ml-mtl-stack](docs/ml-mtl-stack.md) ·
[swipe-model](docs/swipe-model.md) ·
[gift-recommendation-research](docs/gift-recommendation-research.md) ·
[maxi-agentcore-design](docs/maxi-agentcore-design.md) ·
[maxi-product-benchmark](docs/maxi-product-benchmark.md) ·
[maxi-gift-scenario](docs/maxi-gift-scenario.md)

**Backend**
[backend-changelog](docs/backend-changelog.md) — what shipped and why ·
[backend-future-specs](docs/backend-future-specs.md) — designed, not built ·
[backend-scaling-design](docs/backend-scaling-design.md) ·
[api-concurrency-investigation](docs/api-concurrency-investigation-2026-07-13.md)

**Data & catalog**
[data-inventory](docs/data-inventory.md) ·
[data-quality-plan](docs/data-quality-plan.md) ·
[curated-commerce-pilot](docs/curated-commerce-pilot.md) ·
[swipe-product-image-pipeline](docs/swipe-product-image-pipeline.md) ·
[amazon-app-linking](docs/amazon-app-linking.md) ·
[email-order-tracking-research](docs/email-order-tracking-research.md) ·
[json-to-toon-migration](docs/json-to-toon-migration.md)

**Build, release & ops**
[build-benchmarks](docs/build-benchmarks.md) ·
[release-cadence](docs/release-cadence.md) ·
[testflight-deployment](docs/testflight-deployment.md) — the CI path, for when Actions billing is restored ·
[xcode-cloud](docs/xcode-cloud.md) ·
[password-storage-audit](docs/password-storage-audit.md)

**Design & launch**
[design-gap-analysis](docs/design-gap-analysis.md) ·
[launch-research](docs/launch-research.md) ·
[product-hunt-launch](docs/product-hunt-launch.md) ·
[agent-roadmap](docs/agent-roadmap.md) ·
[audits/](docs/audits)

---

<sub>The `/screenshots` folder is outdated web material — not a design reference for the app.</sub>
