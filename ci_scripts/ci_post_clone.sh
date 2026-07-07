#!/bin/sh
# Xcode Cloud post-clone hook (runs automatically after every clone).
#
# The .xcodeproj is not committed — XcodeGen generates it from project.yml —
# and GoogleService-Info.plist is gitignored (it carries the Google OAuth
# client). Xcode Cloud needs both to exist before it resolves the scheme, so
# this script materializes them. See docs/xcode-cloud.md.
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

brew install xcodegen
xcodegen generate

if [ -n "$GOOGLE_SERVICE_INFO_PLIST_B64" ]; then
  echo "$GOOGLE_SERVICE_INFO_PLIST_B64" | base64 -d > Giftmaxxing/GoogleService-Info.plist
  plutil -lint Giftmaxxing/GoogleService-Info.plist
else
  echo "warning: GOOGLE_SERVICE_INFO_PLIST_B64 not set — Google Sign-In will report 'not configured' in this build"
fi
