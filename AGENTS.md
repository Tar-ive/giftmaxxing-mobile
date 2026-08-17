# AGENTS.md — Giftmaxxing

**This is the canonical instruction file for every agent working in this repo** (Claude Code, Codex,
Cursor, Devin). `CLAUDE.md` points here. Nested files override for their subtree: `web/AGENTS.md`
for Next.js work.

**The product is the iOS app.** It ships on the App Store (1.1.2 live) and via TestFlight. `web/` is
a secondary surface; `infra/` is the backend that serves both.

## Build and test

```bash
xcodegen generate                     # ALWAYS first — the .xcodeproj is generated and gitignored
xcodebuild -project Giftmaxxing.xcodeproj -scheme Giftmaxxing \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build

swift test --package-path Packages/GiftmaxxingKit          # module tests — ~2s, run these constantly
xcodebuild test -project Giftmaxxing.xcodeproj -scheme Giftmaxxing -only-testing:GiftmaxxingTests \
  -destination 'platform=iOS Simulator,id=9F1AFADE-7F36-433C-9C68-F9D39E8D279E'   # app tests — ~50s

npm --prefix infra/src test           # backend (node:test) — run before ANY infra deploy
```

97 tests total: 41 in the package, 56 in the app. If that number drops, you lost a test.

## Layout

| Path | What it is |
|---|---|
| `Giftmaxxing/` | The iOS app target — views, stores, app state |
| `Packages/GiftmaxxingKit/` | Local Swift package: `GiftmaxxingCore` (models) and `GiftmaxxingRecommendation` (on-device ranking) |
| `GiftmaxxingShare/` | Share extension — the Instagram/Pinterest → visual search bridge |
| `infra/` | Terraform + the Lambda/App Runner handler (`infra/src/`) and ingest scripts (`infra/ingest/`) |
| `web/` | Next.js app on Vercel — see `web/AGENTS.md` |

## Rules that are not negotiable

**Modules may never import the app target.** `GiftmaxxingCore` and `GiftmaxxingRecommendation` are
consumed by the app, never the reverse. If a module needs app behavior, define a protocol in the
module and conform to it in the app — as `InteractionUploading` does. A layering mistake must stay a
compile error.

**Design tokens only.** Every color, font, radius, spacing and shadow resolves through
`Giftmaxxing/Extensions/Theme.swift`. No hex strings, no `.font(.system(size:))` in a view. A missing
token means extending `Theme.swift` **and** `DESIGN.md` in the same PR. Read `DESIGN.md` before UI work.

**Never auto-merge into `main`.** Open PRs as drafts. A human merges, or the user says "merge #N".
An agent merging without that ask is a bug, not a workflow.

**Ship from `main` only.** In August 2026 an agent released four App Store versions off an unmerged
branch; `main` sat three weeks stale and the next build from it silently regressed the product. If
your work isn't on `main`, it isn't ready to ship.

**`Giftmaxxing/Info.plist` is generated.** Edit `project.yml` and re-run `xcodegen generate`. Same for
anything else in the project file.

## Releasing

CI is dead (GitHub Actions billing — every workflow, ubuntu included, fails in ~4s), so releases are
run locally. Full runbook: `DEPLOY.md`. Short version: archive with `GIT_COMMIT` stamped, export with
`scripts/exportOptions.plist` (`destination: upload` means export *is* the upload), poll
`scripts/asc-api.py`, tag `v<version>`.

## Backend work

`CLOUD.md` is the current architecture. `docs/backend-changelog.md` is what shipped and why;
`docs/backend-future-specs.md` is designed-but-not-built. Deploying `infra/` means **both** the
Lambda (`terraform apply`) and the App Runner container (ECR push + `start-deployment`) — they run
the same code and drift if you do only one.

Terraform ≥ 1.15.6, state in S3 (`giftmaxxing-tfstate-445056752928`), auth via `aws sso login`.
A healthy `terraform plan` shows 0 to add / 0 to destroy. If it wants to create ~98 resources, the
backend config is wrong — do not apply. Portable runbook: `infra/DEPLOY-ANYWHERE.md`.

In a proxied container, run node scripts with `NODE_USE_ENV_PROXY=1` — Node's fetch ignores
`HTTPS_PROXY` and the egress 429s.

## Maintaining this file

Treat it as code, because agents execute it.

- **It changes in the same PR as the behavior it describes.** Never a standalone "update the docs"
  commit weeks later — that drift is how `DEPLOY.md` ended up describing a June pull request.
- **Four valid reasons to edit:** a process changed · an agent made the same mistake twice · an
  architectural decision landed · a command or path moved. Nothing else.
- **Never add:** task notes, changelog entries, plans, or anything an agent can learn by reading the
  code. For each line ask *"would removing this cause a mistake?"* If not, cut it. A bloated file
  gets ignored wholesale.
- **Where things belong:** always-true rules → here (keep under 200 lines) · on-demand workflows →
  `.claude/skills/` · deep reference → `docs/` · must-happen automation → a hook, not a sentence.
- **Ownership:** `.github/CODEOWNERS` covers this file and its siblings. Agents propose; a human
  approves.

Sources for the above: [Anthropic](https://code.claude.com/docs/en/best-practices) ·
[Cursor](https://cursor.com/docs/rules) · [agents.md](https://agents.md/) ·
[Devin](https://docs.devin.ai/onboard-devin/knowledge-onboarding).

## Gotchas that have bitten us

- The App Store Connect key lives at `~/.appstoreconnect/private_keys/AuthKey_254ZRKZ2HP.p8`.
- `web/` lint reports one pre-existing error (`get-app-banner.tsx`); `npm run build` is the real gate.
- The `/screenshots` folder is outdated web material — never use it as an iOS design reference.
- Never `git add -A` here. The working tree carries hundreds of untracked scratch files; stage paths
  explicitly or you will commit 800 files of marketing assets and eval JSON.
