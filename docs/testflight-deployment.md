# GitHub → TestFlight: how it's automated

Pushing to `main` (any change under `Giftmaxxing/`, `GiftmaxxingShare/`, or
`project.yml`) builds a signed Release archive and uploads it to TestFlight
automatically via `.github/workflows/ios-testflight.yml`. There's also a
manual **Run workflow** button (workflow_dispatch) for ad-hoc uploads.

To ship from a `production` branch instead of `main`, change one line
(`branches: [main]`) in the workflow.

## The three ways people do this (and why we picked ours)

| Approach | Pros | Cons |
| --- | --- | --- |
| **Xcode Cloud** (Apple-native CI) | Zero secrets, signing fully managed, TestFlight-native, 25 free compute hrs/mo | Configured in App Store Connect UI, not in-repo; separate CI system from the GitHub Actions we already run |
| **GitHub Actions + fastlane** (match/pilot) | Huge ecosystem, screenshots/metadata automation | Ruby toolchain + a cert repo to maintain; heavyweight for a single app |
| **GitHub Actions + xcodebuild + ASC API key** ← chosen | In-repo, no extra tooling, 3 secrets, Apple cloud signing handles certs AND profiles | Cloud signing needs the API key to have App Manager role |

The chosen path is Apple's modern recommendation: `xcodebuild` authenticated
with an **App Store Connect API key** uses cloud signing to create/fetch the
Apple Distribution certificate and provisioning profiles on the fly
(`-allowProvisioningUpdates`), and `ExportOptions.plist` with
`destination: upload` makes the export step itself do the TestFlight upload —
no `altool`, no Transporter, no .p12 wrangling.

Note: if you'd rather have zero GitHub secrets, Xcode Cloud is the better
pick — open Xcode → Product → Xcode Cloud → Create Workflow, select the
GitHub repo, and set the workflow to "Archive → TestFlight (Internal)" on
main. Both systems can coexist; they'd just produce two builds per push.

## One-time setup

### 1. App Store Connect API key → 3 secrets

Status for this repo: `ASC_KEY_ID` and `ASC_KEY_P8` are **already set** (from
the key at `~/.appstoreconnect/private_keys/AuthKey_254ZRKZ2HP.p8`); only
`ASC_ISSUER_ID` remains.

1. [App Store Connect](https://appstoreconnect.apple.com) → **Users and
   Access** → **Integrations** → **App Store Connect API** → **Team Keys**.
   (Creating a key: **+**, name it, role **App Manager** — needed so cloud
   signing can manage certs/bundle ids/profiles. The `.p8` downloads once.)
2. Copy the **Issuer ID** shown at the top of that page (a UUID).
3. Set the secrets (UI, or `gh secret set NAME`):
   - `ASC_KEY_ID` — the Key ID shown in the key's row
   - `ASC_ISSUER_ID` — the Issuer ID UUID
   - `ASC_KEY_P8` — the full text contents of the `.p8` file

### 2. Distribution certificate — NOT needed by default

The workflow uses Apple **cloud signing**: with the API key authenticated,
`xcodebuild -allowProvisioningUpdates` creates/uses a cloud-managed Apple
Distribution certificate — no local cert, nothing to export.

Only if cloud signing ever fails for the team (rare; some older accounts),
fall back to a classic .p12: Keychain Access → export *Apple Distribution:
<team>* → `base64 -i distribution.p12 | pbcopy` → set `BUILD_CERTIFICATE_B64`
and `P12_PASSWORD`. The workflow picks them up automatically when present.

### 3. App Store Connect app record (likely already done)

TestFlight needs the app to exist once: App Store Connect → My Apps → **+**
→ New App → bundle id `com.giftmaxxing.ios`. The share extension
(`com.giftmaxxing.ios.share`) does NOT need its own app record — it ships
inside the app — but both bundle ids must exist in [Certificates,
Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)
with the right capabilities:

- `com.giftmaxxing.ios` — App Groups (`group.com.giftmaxxing.ios`),
  Sign in with Apple, Push Notifications (per `Giftmaxxing.entitlements`)
- `com.giftmaxxing.ios.share` — App Groups (same group)

Building the app once from Xcode with automatic signing (which whoever is
doing the manual TestFlight submission has already done) registers all of
this; the CI's `-allowProvisioningUpdates` keeps it fresh thereafter.

## How versioning works

- **Build number** (`CURRENT_PROJECT_VERSION`): CI passes the workflow run
  number, and `manageAppVersionAndBuildNumber` in
  `.github/ExportOptions.plist` additionally lets Xcode bump to the next
  free number by asking App Store Connect — so CI uploads never collide
  with manual Xcode uploads, in either order.
- **Marketing version** (`MARKETING_VERSION`, currently `1.0.0`): bump it in
  `project.yml` when starting a new release train; TestFlight groups builds
  under it.

## Interplay with manual submissions

Manual archive-and-upload from Xcode Organizer keeps working unchanged —
`manageAppVersionAndBuildNumber` on the CI side resolves build-number races.
Whoever handles App Store metadata/screenshots/review does that in App Store
Connect as usual; this pipeline only automates *getting builds to TestFlight*.

## Watch it work

- Push to `main` → Actions tab → **TestFlight** workflow (~15–25 min).
- First run on a fresh setup fails fast with a named list of any missing
  secrets.
- When it's green: App Store Connect → TestFlight shows the build in
  "Processing" (5–15 min), then it lands with internal testers automatically.
- `ITSAppUsesNonExemptEncryption` is already `false` in `project.yml`, so
  builds skip the export-compliance questionnaire and go straight to testers.
