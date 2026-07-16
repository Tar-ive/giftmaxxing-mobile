# Xcode Cloud setup

Short version: **you don't need Xcode Cloud to build/ship — GitHub Actions
already does all of it** (see below). But if you want Apple-native CI with
zero GitHub secrets, this repo is now Xcode Cloud-ready; the only remaining
steps are one-time clicks in Xcode/App Store Connect that can't be done
from the repo.

## What GitHub Actions already covers

| Job | Workflow | What it does |
| --- | --- | --- |
| SwiftLint | `.github/workflows/ios-build.yml` | Static lint on every PR/push |
| Build + unit tests | `.github/workflows/ios-build.yml` | Simulator build + XCTest on every PR/push |
| Maestro E2E | `.github/workflows/ios-build.yml` | UI flows against a booted simulator |
| TestFlight upload | `.github/workflows/ios-testflight.yml` | Signed Release archive → TestFlight on every push to `main` |

So Xcode Cloud is *optional*, not required. Both can coexist — they'd just
produce two builds per push to `main` (disable one of the archive paths if
that's noisy).

## Xcode Cloud custom scripts

`ci_scripts/` is **gitignored** — the previous `ci_post_clone.sh` was failing
Archive (`Running ci_post_clone.sh script failed`). Prefer GitHub Actions
(`ios-testflight.yml`) for CI/TestFlight. If you re-enable Xcode Cloud later,
add a local-only `ci_scripts/ci_post_clone.sh` (xcodegen + GoogleService-Info)
or commit a committed `.xcodeproj` so Archive doesn't need the hook.

## One-time setup (must be done by an Apple Developer account holder)

Follows [Apple's guide](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow/):

1. **Prereqs** (mostly already done for TestFlight): Apple Developer Program
   membership, app record for `com.giftmaxxing.ios` in App Store Connect,
   and admin access.
2. Open the project locally: `xcodegen generate && open Giftmaxxing.xcodeproj`.
3. Xcode → **Integrate ▸ Create Workflow…** (or Report navigator → Cloud tab)
   → select the **Giftmaxxing** product → **Next**.
4. Review the default workflow (branch: `main`, action: Archive) and press
   **Set Up**. Sign in with your Apple ID if prompted.
5. **Grant Xcode Cloud access to the GitHub repo**: Xcode redirects you to
   App Store Connect → GitHub, where you install the "Xcode Cloud" GitHub App
   on `Tar-ive/giftmaxxing-mobile`.
6. In App Store Connect → your app → **Xcode Cloud** → the workflow →
   **Environment**, add environment variable `GOOGLE_SERVICE_INFO_PLIST_B64`
   (check *Secret*). Value: `base64 -i Giftmaxxing/GoogleService-Info.plist | pbcopy`.
7. Press **Start Build**. Signing is fully managed by Apple — no certs,
   profiles, or API keys needed.

Suggested workflows once running:

- **PR workflow**: Build + Test on pull requests to `main`.
- **Release workflow**: Archive → TestFlight (Internal Testing) on push to
  `main` — equivalent to `ios-testflight.yml`; keep only one of the two
  enabled to avoid duplicate TestFlight builds.
