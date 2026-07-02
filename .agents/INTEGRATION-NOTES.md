# Integration notes — 2026-07-02

PRs #2 (iOS-native architecture) and #3 (behavioral analytics) are **merged into
`origin/main`** (`c48e16c`). Local `main` in this working tree is intentionally
left at `8b5e32f` because uncommitted on-device-reranking work is in progress
here (see `docs/on-device-reranking.md`).

## What landed on main

- **PR #2**: Sign in with Apple → Cognito (`Auth/`), SwiftData offline-first
  (`Data/` — CachedPost/CachedInteraction/CachedEvent/PendingAction, SyncEngine,
  OfflineQueue), APNs push (`Network/PushManager.swift`), `CachedAsyncImage` +
  prefetch (`Network/ImageLoader.swift`), mobile Lambda routes
  (`infra/src/mobile-routes.mjs`), `infra/cognito.tf`, `infra/sns-apns.tf`.
- **PR #3**: `Analytics/` (AnalyticsEngine, AnalyticsEvent, ImpressionTracker),
  swipe telemetry, `infra/analytics.tf`, `infra/src/analytics-routes.mjs`.
- Conflict resolutions + fixes on main: unified `SwipeViewModel` signatures
  `swipeRight/Left(velocity:context:)` and `onDragEnd(translation:velocity:context:)`;
  `FeedViewModel.loadFeed(context:)`/`toggleLike/Save(for:context:)`; removed
  duplicate `DeltaSyncResponse` (lives in `Models/APIModels.swift`);
  `OnboardingView(isOnboardingComplete:)` binding wired in `ContentView`;
  `UpcomingEvent → GiftEvent` conversion in `SyncEngine.syncEvents`.

## Rebase guidance for the reranking work in this tree

Commit to a branch, then merge/rebase onto `origin/main`. Expected hotspots:

- **`Services/FeedViewModel.swift`** — full-file conflict. Main's version is
  SwiftData cache-first with `context:` params; local version is the
  over-fetch-40/serve-12 ranked buffer. Unify: keep `loadFeed(context:)`
  signature, load cache first, then fetch+rank via `OnDeviceRanker`.
- **`Services/APIClient.swift`** — local CloudFront `baseURL`
  (`d21osnvwewgoao.cloudfront.net`), `fetchVectors`, `sendInteractionsBatch`
  are additive; main added `applyAuth` bearer tokens + `/mobile/*` endpoints.
  Note main now has THREE interaction paths: `recordInteraction` (single),
  `batchRecordInteractions` (`/mobile/interactions/batch`, PR #3), and the
  local `InteractionQueue` → `POST /interactions {items}` batch. Pick one
  batching strategy (local InteractionQueue + killswitch-aware `/interactions`
  batch is the one the backend handler.mjs change supports).
- **`Views/Swipe/SwipeView.swift`** / **`Views/Feed/FeedView.swift`** — keep
  main's analytics + prefetch + offline-queue calls, add local taste-signal
  recording alongside.
- **`Models/APIModels.swift` / `Models/Post.swift`** — local facet fields
  (recipient/occasion/category/domain/qualityScore/feedEligible) are additive.
- **`infra/variables.tf`** — trivial; both sides touched.
- After resolving: `xcodegen generate` (project.yml changed on main) and build.
