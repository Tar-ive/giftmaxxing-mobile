# Guest boundary — anonymous browser swiping → app/account conversion

**Date:** 2026-07-02 · Implements the Instagram-style split: shared content is
fully usable anonymously in the mobile browser; owning/managing anything
requires an account (or the app).

## 1. Research: how established platforms draw the line

| Platform | Anonymous web can… | Wall appears when… | Conversion surfaces |
|---|---|---|---|
| Instagram | view a shared post/reel/profile | liking, commenting, following, scrolling past a few items | persistent top banner + post-content interstitial + Smart App Banner |
| TikTok | watch shared video + a short feed teaser | engaging or after N videos | "open app" sheet on every scroll pause |
| Pinterest | view a pin | saving, clicking through boards | login wall + app banner |

Common pattern: **let the shared task complete friction-free** (that's the
viral loop), then convert at the **peak-intent moment** (task completion), with
a **persistent but dismissible** app prompt visible from first paint. Hard-gate
everything that stores or manages state on an identity.

## 2. Giftmaxxing boundary matrix (now enforced)

| Action | Signed-out (browser) | Where enforced |
|---|---|---|
| Open a shared challenge + swipe + submit taste | ✅ full flow, no account | `web/app/invite/[code]` + public `POST /connections` |
| Share your own challenge | ✅ (attributed to persistent anon id) | `web/app/challenge` + `lib/anon.ts`; iOS `ChallengeView` + `InteractionQueue.anonymousUserId` |
| Browse the product feed teaser | ✅ read-only public GETs | `/feed`, `/pins`, `/recommendations` public routes |
| See challenge responses | ❌ sign in | `GET /connections` auth-only; iOS `SignInWall`; web `/feed/activity` behind `AuthGate` |
| Enter the app shell (feed, pools, events, profile, Maxi) | ❌ sign in | `web/app/feed/layout.tsx` `AuthGate` (Clerk) |
| Claim anon-collected responses | on sign-in, automatic | `POST /connections/claim` (auth-bound) + `AccountSync` |

## 3. Conversion moments added (this change)

- **From first paint:** dismissible "better in the app" banner on the invite
  welcome + swipe screens (`components/app/get-app-banner.tsx`), plus Safari's
  native Smart App Banner site-wide (`itunes` metadata in `app/layout.tsx`).
- **Peak intent (post-swipe reveal):** `components/app/app-download-cta.tsx` —
  primary "Download on the App Store" block, with the existing Clerk
  `GuestClaimCard` ("manage on web") right below it.
- **In-app (iOS):** post-swipe "Challenge a friend" CTA + `ChallengeView`
  (create/share works signed-out; the Responses section is the sign-in wall).

All app-store surfaces are env-gated and render nothing until a listing exists:
`NEXT_PUBLIC_APP_STORE_URL` (banner + CTA) and `NEXT_PUBLIC_APPLE_APP_ID`
(Smart App Banner). Set both in Vercel when the app ships (TestFlight link
works for beta).

## 4. iOS pieces

- `Giftmaxxing/Services/InviteLink.swift` — same base64url-JSON invite code the
  web decodes (`web/lib/invite.ts`), pointed at the production site URL.
- `Giftmaxxing/Views/Challenge/ChallengeView.swift` — personalize + `ShareLink`
  + auth-gated responses list (`APIClient.fetchConnections`).
- Entry points: More tab "Gift Challenge" card, Swipe toolbar share icon, and
  the swipe-complete screen CTA.

## 5. Open follow-ups

- Universal links (open a giftmaxxing.app link directly in the app when
  installed): needs an `apple-app-site-association` file on the web origin +
  Associated Domains entitlement + real Team ID at signing time.
- Clerk on iOS: `ChallengeResponsesSection` already calls the auth-gated API
  and shows the wall when signed out; wiring real Clerk sessions makes it live.
- Deferred deep links (install → land on your challenge results) via the
  App Store `appArgument`/clipboard handoff once a listing exists.
