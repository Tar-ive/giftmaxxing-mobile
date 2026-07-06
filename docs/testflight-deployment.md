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
| **GitHub Actions + xcodebuild + ASC API key** ← chosen | In-repo, no extra tooling, 5 secrets, uses Apple's own cloud provisioning | You export one .p12 by hand at setup time |

The chosen path is Apple's modern recommendation: `xcodebuild` authenticated
with an **App Store Connect API key** handles provisioning profiles on the fly
(`-allowProvisioningUpdates`), and `ExportOptions.plist` with
`destination: upload` makes the export step itself do the TestFlight upload —
no `altool`, no Transporter.

Note: if you'd rather have zero GitHub secrets, Xcode Cloud is the better
pick — open Xcode → Product → Xcode Cloud → Create Workflow, select the
GitHub repo, and set the workflow to "Archive → TestFlight (Internal)" on
main. Both systems can coexist; they'd just produce two builds per push.

## One-time setup (≈15 minutes)

### 1. App Store Connect API key → 3 secrets

1. [App Store Connect](https://appstoreconnect.apple.com) → **Users and
   Access** → **Integrations** → **App Store Connect API** → **Team Keys** →
   **+**.
2. Name it `github-actions`, role **App Manager** (needed so cloud
   provisioning can register bundle ids / profiles).
3. Download the `AuthKey_XXXXXXXXXX.p8` (downloadable **once**).
4. Create the GitHub secrets (repo → Settings → Secrets and variables →
   Actions):
   - `ASC_KEY_ID` — the Key ID shown in the row (e.g. `2X9R4HXF34`)
   - `ASC_ISSUER_ID` — Issuer ID at the top of that page (a UUID)
   - `ASC_KEY_P8` — the full text contents of the `.p8` file

### 2. Apple Distribution certificate → 2 secrets

On any Mac that has the team's **Apple Distribution** certificate (Xcode →
Settings → Accounts → Manage Certificates… → **+** → Apple Distribution if
none exists yet):

1. Open **Keychain Access** → My Certificates → right-click *Apple
   Distribution: <team>* → **Export…** → `.p12`, choose a password.
2. `base64 -i distribution.p12 | pbcopy`
3. Create the secrets:
   - `BUILD_CERTIFICATE_B64` — the base64 you just copied
   - `P12_PASSWORD` — the export password

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
