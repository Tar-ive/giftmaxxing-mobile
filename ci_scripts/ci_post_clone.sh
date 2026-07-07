#!/bin/sh
# Xcode Cloud bootstrap — runs right after clone, before Xcode builds.
# Mirrors what .github/workflows/ios-testflight.yml does on GitHub Actions:
#
#  1. Regenerate the Xcode project from project.yml. The committed pbxproj
#     goes stale (new source files land via folder globs, not manual project
#     edits), so every CI build regenerates instead of trusting it.
#  2. Materialize the gitignored GoogleService-Info.plist (it carries the
#     Google OAuth client for Sign-In). Set GOOGLE_SERVICE_INFO_PLIST_B64 as
#     a SECRET environment variable in the Xcode Cloud workflow editor:
#     App Store Connect → Xcode Cloud → your workflow → Environment.
#
# Signing needs no setup here — Xcode Cloud manages certificates and
# profiles for both bundle ids (app + share extension) itself.
set -e
cd "$CI_PRIMARY_REPOSITORY_PATH"

brew install xcodegen
xcodegen generate

if [ -n "$GOOGLE_SERVICE_INFO_PLIST_B64" ]; then
  echo "$GOOGLE_SERVICE_INFO_PLIST_B64" | base64 --decode > Giftmaxxing/GoogleService-Info.plist
  echo "GoogleService-Info.plist installed"
else
  echo "warning: GOOGLE_SERVICE_INFO_PLIST_B64 not set — Google Sign-In will report 'not configured' in this build"
fi
