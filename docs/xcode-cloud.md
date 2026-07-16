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

## Why this repo needs `ci_scripts/ci_post_clone.sh`

Xcode Cloud clones the repo and expects an `.xcodeproj` at the root.
`Giftmaxxing.xcodeproj` is **gitignored** and generated from `project.yml` via
XcodeGen, so Archive without the hook fails with *Project Giftmaxxing.xcodeproj
does not exist*.

[`ci_scripts/ci_post_clone.sh`](../ci_scripts/ci_post_clone.sh) (Apple's
post-clone hook) does:

1. Install XcodeGen if needed (`brew`, with retries / no auto-update — Xcode
   Cloud `brew` is flaky), then `xcodegen generate`
2. Optionally decode `GOOGLE_SERVICE_INFO_PLIST_B64` (Xcode Cloud Secret) into
   `Giftmaxxing/GoogleService-Info.plist`

**Why an earlier build showed `ci_post_clone.sh … exited with code 1`:** Apple's
UI only surfaces that one-liner (no script stdout in the GitHub check summary).
The script content was unchanged between a green Archive (#61) and a red one
(#62); `project.yml` didn't change either. Most likely a transient
`brew install xcodegen` / Homebrew network failure on Xcode Cloud. The restored
script skips brew when `xcodegen` is already present, retries once, and verifies
the `.xcodeproj` before exiting 0.

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
