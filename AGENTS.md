# AGENTS.md — Giftmaxxing (repo root)

See `CLAUDE.md` and `CLOUD.md` for product/architecture memory, and
`web/AGENTS.md` for Next.js-specific rules (notably: this Next.js has breaking
changes — read `web/node_modules/next/dist/docs/` before writing Next code — and
the `web/app/privacy/page.tsx` guard that CI enforces).

## Cursor Cloud specific instructions

### Do NOT auto-merge into `main`
- **Never merge a PR into `main` unless the user explicitly asks to merge that
  specific PR** (e.g. “merge #50” / “merge this”). Creating or updating a PR is
  fine; merging is not.
- Open PRs as **drafts** by default (`draft: true`). Mark ready for review only
  when the user asks.
- Do not enable GitHub auto-merge (`gh pr merge --auto`, `autoMergeRequest`,
  etc.). Repo `allow_auto_merge` should stay off.
- If an automation / other agent is merging without an explicit user request,
  stop and leave the PR open for human review instead.

### Layout & what runs where
- `web/` — Next.js 16 app (the primary locally-runnable product). Node 22, npm
  (has `web/package-lock.json`). This is what a developer runs and tests locally.
- `infra/` — Terraform serverless backend (DynamoDB + Lambda + API Gateway),
  already deployed to AWS `us-east-1`. Needs real AWS credentials to `plan`/`apply`.
- `infra/ingest/` and `infra/src/` — Node scripts / Lambda bundle. They run against
  AWS (Bedrock, S3 Vectors, DynamoDB) and need AWS credentials to do anything real.

### Running the web app (no secrets required)
- Standard scripts live in `web/package.json`: `npm run dev`, `npm run build`,
  `npm run lint`.
- The dev server runs on `http://localhost:3000`. Start it in a background/tmux
  session — do not block on it.
- The app reads its backend from `NEXT_PUBLIC_API_URL`, which defaults to a **public**
  CloudFront URL committed in `web/.env.example`; no secret is needed to run locally.
  When the API is unreachable, the app degrades gracefully to bundled fallback data
  (e.g. `web/lib/seed-pins.ts`), so the feed, onboarding, swipe, and like/save flows
  all work fully offline. AWS credentials are only needed for `infra/` deploys and
  `infra/ingest` scripts, not for local app development.
- Clerk auth is optional: without `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` /
  `CLERK_SECRET_KEY` the app runs with auth disabled and everything else works.

### Lint caveat (important)
- `npm run lint` currently reports **1 pre-existing error** (a
  `react-hooks/set-state-in-effect` in `web/components/app/get-app-banner.tsx`) plus
  several warnings. This is expected on a clean checkout and is **not** caused by your
  changes. CI runs lint with `continue-on-error: true` (see
  `.github/workflows/ci.yml`), so it does not block; `npm run build` is the gating
  check.

### infra/ toolchain (Terraform + AWS)
- **Full portable runbook: `infra/DEPLOY-ANYWHERE.md`** (toolchain install, SSO auth,
  state handling + S3-backend migration, plan/apply). Read it before touching `infra/`.
- Deploying `infra/` needs the **AWS CLI v2** and **Terraform `>= 1.15.6`** (neither
  ships in the base image). Both are installed into `/usr/local/bin` in the current VM
  snapshot. **Terraform version matters:** the deployed state was written by 1.15.6, so
  older Terraform will refuse to read it (`versions.tf` only pins `>= 1.6`, but the
  state forces `>= 1.15.6`). AWS provider is `hashicorp/aws ~> 5.60`. These are system
  deps, NOT in the update script; reinstall per `DEPLOY-ANYWHERE.md` if a VM lacks them.
- **State is on an S3 remote backend** (configured in `versions.tf`): bucket
  `giftmaxxing-tfstate-445056752928`, key `infra/dev/terraform.tfstate`, versioned +
  SSE-S3, S3-native locking (`use_lockfile`, no DynamoDB table). Any machine just runs
  `terraform init` to share the locked state — no more copying `terraform.tfstate`
  around. You still need the gitignored `terraform.tfvars` locally. A healthy
  `terraform plan` shows **0 to add / 0 to destroy** (a few in-place Lambda
  `source_code_hash` updates are expected drift). If `plan` ever wants to CREATE the ~98
  existing resources, the backend/state is misconfigured — do NOT apply.
- **Auth via AWS SSO** (preferred over static keys): `aws configure sso` once (account
  `445056752928`, admin-capable role, e.g. profile `giftmaxxing_dev_cursor_cloud`), then
  `aws sso login --profile <name>`; headless VMs print a device-code URL. Export
  `AWS_PROFILE` + `AWS_REGION=us-east-1`. SSO sessions expire — re-run `aws sso login`
  when `aws sts get-caller-identity` fails.
- Before `apply`, run `npm --prefix infra/src ci` so the Lambda bundle includes
  `@aws-sdk/client-s3vectors` (not in the nodejs20.x runtime). Resource/route reference
  + cost runbook: `infra/README.md`. `infra/ingest` scripts need creds via
  `set -a; source ../../.env; set +a` OR an active `AWS_PROFILE`.

### Onboarding gate
- The feed is gated behind onboarding (`web/components/app/onboarding-gate.tsx`): a
  fresh browser profile with no `localStorage` is redirected to `/onboarding`. To reach
  `/feed` you must complete the onboarding wizard first (or seed the localStorage
  profile). The wizard is the app's core first-run flow.
