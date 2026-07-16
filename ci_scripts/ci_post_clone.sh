#!/bin/sh
# Xcode Cloud bootstrap — runs right after clone, before Xcode builds.
#
# Why this exists: Giftmaxxing.xcodeproj is gitignored and generated from
# project.yml via XcodeGen. Without this hook, Archive fails with:
#   "Project Giftmaxxing.xcodeproj does not exist at the root of the repository"
#
# Hardening notes (vs the earlier one-liner brew install):
# - Xcode Cloud only reports "exited with code 1" for script failures; the
#   previous script was identical to a successful build (#61) then failed on
#   #62 with no project.yml change — most often `brew install` flaking on
#   Xcode Cloud's network/proxy (Apple Forums: GIT_HTTP_MAX_REQUESTS=1,
#   HOMEBREW_NO_AUTO_UPDATE=1).
# - Skip brew when xcodegen is already on PATH; retry install once; verify
#   the generated .xcodeproj before exiting 0.
#
# Optional: set GOOGLE_SERVICE_INFO_PLIST_B64 (Secret) in the Xcode Cloud
# workflow Environment to materialize the gitignored GoogleService-Info.plist.
set -e

echo "==> ci_post_clone.sh starting"

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-}"
if [ -z "$REPO_ROOT" ]; then
  # Xcode Cloud runs this from ci_scripts/; fall back to parent of script dir.
  SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
  REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
fi
cd "$REPO_ROOT"
echo "==> repo root: $REPO_ROOT"

# Reduce Homebrew/GitHub flakiness on Xcode Cloud (concurrent HTTP via proxy).
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1
export GIT_HTTP_MAX_REQUESTS=1

install_xcodegen() {
  echo "==> brew install xcodegen (attempt $1)"
  brew install xcodegen
}

if command -v xcodegen >/dev/null 2>&1; then
  echo "==> xcodegen already installed: $(command -v xcodegen)"
else
  if ! install_xcodegen 1; then
    echo "==> first brew install failed; retrying once..."
    sleep 3
    install_xcodegen 2
  fi
fi

echo "==> xcodegen generate"
xcodegen generate

if [ ! -d "Giftmaxxing.xcodeproj" ]; then
  echo "error: Giftmaxxing.xcodeproj missing after xcodegen generate" >&2
  ls -la
  exit 1
fi
echo "==> Giftmaxxing.xcodeproj ready"

if [ -n "${GOOGLE_SERVICE_INFO_PLIST_B64:-}" ]; then
  echo "$GOOGLE_SERVICE_INFO_PLIST_B64" | base64 --decode > Giftmaxxing/GoogleService-Info.plist
  echo "==> GoogleService-Info.plist installed"
else
  echo "==> warning: GOOGLE_SERVICE_INFO_PLIST_B64 not set — Google Sign-In will report 'not configured' in this build"
fi

echo "==> ci_post_clone.sh done"
