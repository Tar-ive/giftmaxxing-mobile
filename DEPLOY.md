# DEPLOY.md — how Giftmaxxing ships

Three deploy targets, three processes. Everything here has been run on this machine; if a command
doesn't work, fix the command or fix this file.

> **CI is dead.** Every GitHub Actions workflow — including the ubuntu-only web CI — fails in about
> four seconds because Actions billing is blocked. Nothing auto-deploys and no PR gets automated
> checks. Restoring billing at [github.com/settings/billing](https://github.com/settings/billing) is
> the prerequisite for going back to the workflow path in `docs/testflight-deployment.md`.

---

## 1. iOS → TestFlight (the live process)

Run from a Mac with Xcode. The App Store Connect key must be at
`~/.appstoreconnect/private_keys/AuthKey_254ZRKZ2HP.p8`.

### Preflight — never skip

```bash
git switch main && git pull --ff-only            # ship from main only
xcodegen generate
xcodebuild -project Giftmaxxing.xcodeproj -scheme Giftmaxxing \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
swift test --package-path Packages/GiftmaxxingKit
xcodebuild test -project Giftmaxxing.xcodeproj -scheme Giftmaxxing -only-testing:GiftmaxxingTests \
  -destination 'platform=iOS Simulator,id=9F1AFADE-7F36-433C-9C68-F9D39E8D279E'
```

97 tests must pass (41 package + 56 app).

### Version

Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, then `xcodegen generate`.
Check what already exists first — build numbers are unique per app, and shipping a *lower* marketing
version files the build under an older TestFlight train and reads as a downgrade to testers:

```bash
python3 scripts/asc-api.py '/v1/builds?filter[app]=6788124639&sort=-uploadedDate&limit=5&fields[builds]=version,uploadedDate,processingState'
```

### Archive — stamp the commit

```bash
SHA=$(git rev-parse --short HEAD)
xcodebuild archive -project Giftmaxxing.xcodeproj -scheme Giftmaxxing -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/Giftmaxxing-<BUILD>.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_254ZRKZ2HP.p8 \
  -authenticationKeyID 254ZRKZ2HP -authenticationKeyIssuerID 77c91aba-1d1e-431d-b9a3-a4dadd970467 \
  CURRENT_PROJECT_VERSION=<BUILD> GIT_COMMIT=$SHA -quiet
```

`GIT_COMMIT` becomes the `GitCommit` Info.plist key, shown in You → Settings. Without it you cannot
answer "which commit is this build?" later — which is exactly the hole that made tracing 1.1.2 take
a session-log excavation.

### Export — export *is* the upload

```bash
PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild -exportArchive \
  -archivePath /tmp/Giftmaxxing-<BUILD>.xcarchive \
  -exportOptionsPlist scripts/exportOptions.plist \
  -exportPath /tmp/Giftmaxxing-<BUILD>-export \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_254ZRKZ2HP.p8 \
  -authenticationKeyID 254ZRKZ2HP -authenticationKeyIssuerID 77c91aba-1d1e-431d-b9a3-a4dadd970467
```

`scripts/exportOptions.plist` sets `destination: upload`, so this step uploads to App Store Connect —
there is no separate altool/Transporter call. The sanitized `PATH` keeps Homebrew's Python off the
upload path. `manageAppVersionAndBuildNumber` lets Apple pick the next free build number, so manual
and scripted uploads can interleave.

Then poll until the build is `VALID` (2–5 minutes):

```bash
python3 scripts/asc-api.py '/v1/builds?filter[app]=6788124639&sort=-uploadedDate&limit=3&fields[builds]=version,processingState'
```

This puts the build in **TestFlight only**. It does not create an App Store version and does not
submit anything for review.

### Expiring a bad build

```bash
python3 scripts/asc-api.py "/v1/builds/<BUILD_ID>" PATCH \
  '{"data":{"type":"builds","id":"<BUILD_ID>","attributes":{"expired":true}}}'
```

---

## 2. iOS → App Store

`scripts/app-store-release.mjs` releases the newest version sitting in `PENDING_DEVELOPER_RELEASE`,
enables Apple's phased rollout, and **tags the released commit `v<version>`**:

```bash
node scripts/app-store-release.mjs              # dry run — prints the candidate, changes nothing
node scripts/app-store-release.mjs --release    # releases + tags + pushes the tag
```

Cadence and gates: `docs/release-cadence.md` (Thursday releases, manual release type). Historical
releases `v1.0.1`–`v1.1.2` were tagged retroactively, with commits inferred from build upload times
because those builds predate the `GitCommit` stamp.

---

## 3. Backend → AWS

```bash
cd infra
npm --prefix src ci                 # the Lambda bundle needs @aws-sdk/client-s3vectors
npm --prefix src test               # must pass before you apply
terraform init && terraform plan -out=tfplan
terraform apply tfplan
```

A healthy plan is **0 to add, 0 to destroy** (in-place `source_code_hash` updates are expected). If
it wants to create ~98 resources, the backend/state is misconfigured — stop.

**Terraform is only half a deploy.** The same handler also runs as a container behind CloudFront, so
after applying: rebuild and push the ECR image, then `aws apprunner start-deployment`. Skipping this
leaves Lambda and App Runner serving different code.

Auth is AWS SSO: `aws sso login --profile <name>`, then export `AWS_PROFILE` and
`AWS_REGION=us-east-1`. Full portable runbook: `infra/DEPLOY-ANYWHERE.md`.

Verify: `curl -s .../healthz` and one real `/feed` page.

---

## 4. Web → Vercel

Push to `main`. Vercel auto-deploys from GitHub with Root Directory = `web`. Do **not** deploy with
the Vercel CLI. The gating check is `npm --prefix web run build`; lint reports one known pre-existing
error and does not block.
