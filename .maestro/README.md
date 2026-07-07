# E2E flows (Maestro)

Maestro drives the app through the OS accessibility layer — its iOS driver is
itself a Swift XCUITest bundle that Maestro installs on the simulator — so our
SwiftUI app is tested exactly as a user sees it, no app-code instrumentation.

## How sign-in works in E2E

The app requires an account (no guest door). Flows authenticate as a real
Cognito user pool account, `e2e@giftmaxxing.dev`, passed via launch arguments
into a DEBUG-only hook (`E2ESupport.swift` → `AuthManager.signInWithPassword`,
Cognito `USER_PASSWORD_AUTH`). Release builds ignore the hook.

The password lives in `~/.giftmaxxing-e2e-password` on the dev machine (and in
CI would come from a secret). It is never committed. Rotate it any time with:

```bash
aws cognito-idp admin-set-user-password --user-pool-id us-east-1_hzmIIObu4 \
  --username e2e@giftmaxxing.dev --password "<new>" --permanent
```

## Running

```bash
# One-time per shell (Maestro CLI is at ~/.maestro/bin, needs brew's openjdk):
export JAVA_HOME=/opt/homebrew/opt/openjdk
export PATH="$JAVA_HOME/bin:$HOME/.maestro/bin:$PATH"

# Build + install the Debug app on a booted simulator, then:
maestro test \
  -e E2E_EMAIL=e2e@giftmaxxing.dev \
  -e E2E_PASSWORD="$(cat ~/.giftmaxxing-e2e-password)" \
  .maestro/01_smoke.yaml

# Whole suite (03 writes a circle to the dev backend — run deliberately):
maestro test -e E2E_EMAIL=e2e@giftmaxxing.dev \
  -e E2E_PASSWORD="$(cat ~/.giftmaxxing-e2e-password)" .maestro/
```

## Flows

- `01_smoke.yaml` — sign-in wall shows Apple/Google only (guest door stays
  dead), then credentialed launch reaches all five tabs.
- `02_circles_join_link.yaml` — the paste-a-circle-link door rejects garbage.
- `03_circle_create_e2e.yaml` — creates a real circle end-to-end (backend
  write; keep out of per-commit loops).
