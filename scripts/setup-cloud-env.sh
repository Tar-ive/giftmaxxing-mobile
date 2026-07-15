#!/usr/bin/env bash
# Bootstrap for remote/cloud Claude Code environments (and fresh machines).
#
# Provisions two things, both driven by secrets set in the environment
# settings — never committed to the repo:
#
#   1. ~/.aws/config — the giftmaxxing dev AWS SSO (IAM Identity Center)
#      profile. Credentials still require an interactive browser login:
#        aws sso login --profile dev_sso_giftmaxxing
#      then either `export AWS_PROFILE=dev_sso_giftmaxxing` or pass
#      `--profile dev_sso_giftmaxxing` per command.
#
#   2. ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8 — the App
#      Store Connect API key, materialized from env secrets. This is the
#      standard path searched by xcodebuild/altool and hardcoded in
#      scripts/asc-api.py + scripts/asc-upload-screenshots.py.
#
# Required environment secrets for the ASC half (skipped if unset):
#   ASC_KEY_ID      App Store Connect API key ID (e.g. 254ZRKZ2HP)
#   ASC_ISSUER_ID   Issuer ID UUID from the same Integrations page
#   ASC_KEY_P8      Full text contents of the AuthKey_<KEYID>.p8 file
#
# Idempotent: safe to run on every environment start.
set -euo pipefail

# ---------------------------------------------------------------- AWS SSO ---
AWS_CONFIG="$HOME/.aws/config"
mkdir -p "$HOME/.aws"

if [ -f "$AWS_CONFIG" ] && grep -q '^\[sso-session giftmaxxing_dev_sso\]' "$AWS_CONFIG"; then
  echo "aws: SSO config already present in $AWS_CONFIG — leaving it untouched"
else
  cat >> "$AWS_CONFIG" <<'EOF'
[default]
region = us-east-1

[profile dev_sso_giftmaxxing]
sso_session = giftmaxxing_dev_sso
sso_account_id = 445056752928
sso_role_name = AdministratorAccess
region = us-east-1

[sso-session giftmaxxing_dev_sso]
sso_start_url = https://identitycenter.amazonaws.com/ssoins-72234e32be03598b
sso_region = us-east-1
sso_registration_scopes = sso:account:access
EOF
  echo "aws: wrote SSO profile dev_sso_giftmaxxing to $AWS_CONFIG"
fi
echo "aws: authenticate with -> aws sso login --profile dev_sso_giftmaxxing"

# --------------------------------------------- App Store Connect API key ---
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_KEY_P8:-}" ]; then
  ASC_DIR="$HOME/.appstoreconnect/private_keys"
  KEY_FILE="$ASC_DIR/AuthKey_${ASC_KEY_ID}.p8"
  mkdir -p "$ASC_DIR"
  printf '%s\n' "$ASC_KEY_P8" > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  echo "asc: wrote $KEY_FILE"
  if [ -z "${ASC_ISSUER_ID:-}" ]; then
    echo "asc: WARNING — ASC_ISSUER_ID is not set; JWT minting will fail" >&2
  fi
else
  echo "asc: ASC_KEY_ID / ASC_KEY_P8 not set — skipping App Store Connect key install"
fi
