# AGENTS.md — Giftmaxxing (repo root)

See `CLAUDE.md` and `CLOUD.md` for product/architecture memory, and
`web/AGENTS.md` for Next.js-specific rules (notably: this Next.js has breaking
changes — read `web/node_modules/next/dist/docs/` before writing Next code — and
the `web/app/privacy/page.tsx` guard that CI enforces).

## Cursor Cloud specific instructions

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
- Deploying `infra/` needs the **AWS CLI v2** and **Terraform** (neither ships in the
  base image). Both are installed into `/usr/local/bin` in the current VM snapshot
  (aws-cli v2, terraform 1.9.x — provider is `hashicorp/aws ~> 5.60`). They are NOT in
  the update script (system deps, not codebase deps); if a fresh VM lacks them,
  reinstall aws-cli v2 and a Terraform `>= 1.6` binary.
- State is **local** (no remote backend); `terraform init` in `infra/` just downloads
  providers (no creds needed). Region/env default to `us-east-1` / `dev`.
- **Auth via AWS SSO** (preferred over static keys): run `aws configure sso` once
  (supply your SSO start URL + region, pick account `445056752928` + a role that can
  manage the stack, name the profile e.g. `giftmaxxing`), then `aws sso login
  --profile giftmaxxing`. This VM is headless, so the CLI prints a verification URL +
  code to open in a browser on any device. Export `AWS_PROFILE=giftmaxxing` (or pass
  `--profile`) for `aws`/`terraform`. SSO sessions are short-lived — re-run `aws sso
  login` when `aws sts get-caller-identity` starts failing.
- Standard Terraform workflow lives in `infra/README.md` (`terraform plan` /
  `terraform apply`, then `terraform output`). `infra/ingest` scripts expect creds
  loaded via `set -a; source ../../.env; set +a` OR an active `AWS_PROFILE`.

### Onboarding gate
- The feed is gated behind onboarding (`web/components/app/onboarding-gate.tsx`): a
  fresh browser profile with no `localStorage` is redirected to `/onboarding`. To reach
  `/feed` you must complete the onboarding wizard first (or seed the localStorage
  profile). The wizard is the app's core first-run flow.
