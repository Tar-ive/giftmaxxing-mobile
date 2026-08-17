# Weekly iOS release train

Giftmaxxing ships publicly on **Thursday morning**, not Friday. That keeps one
staffed business day for crash monitoring, feature-flag rollback and App Store
intervention before the weekend.

| Time (America/Chicago) | Gate |
|---|---|
| Tuesday 10:00 | `main` becomes the TestFlight release candidate |
| Wednesday 12:00 | QA sign-off, metadata check, submit the candidate to review |
| Thursday 10:00 | Release an approved version with Apple's seven-day phased rollout |
| Friday | Monitor only; emergency hotfixes may use manual workflow dispatch |

## Rules

- Merge small changes continuously, but keep unfinished behavior behind a
  server-side feature flag that defaults off.
- Do not upload a TestFlight build for every merge. The scheduled candidate is
  the only normal weekly build.
- App Store versions use **manual release**. If Apple approval misses Thursday,
  the version waits for the next Thursday instead of appearing unpredictably.
- User-visible API and recommendation-policy changes follow the same Thursday
  window. Data corrections, safety fixes and kill-switch changes may ship at
  any time.
- Pause Apple's phased release if crash-free sessions, sign-in, purchases,
  recommendation latency or safety metrics regress.

## Automation

- `.github/workflows/ios-testflight.yml`: Tuesday TestFlight candidate.
- `.github/workflows/app-store-release.yml`: Thursday release of the newest
  `PENDING_DEVELOPER_RELEASE` version; no-op when nothing is approved.
- `scripts/app-store-release.mjs`: dry-run by default; `--release` performs the
  App Store release, ensures phased rollout is configured, and tags the
  released commit `v<version>` (idempotent; a tag failure never fails the
  release).

## Traceability

Every build stamps the commit that produced it: `GIT_COMMIT` is passed at
archive time and surfaces as the `GitCommit` Info.plist key, shown in
You → Settings next to the version and build number. Public releases also carry
a git tag — `v1.0.1` … `v1.1.2` were added retroactively, with the commit
inferred from each build's App Store Connect upload time (those builds predate
the stamp, so they are best-effort).

GitHub Actions billing must be healthy for either scheduled workflow to run.
Until then, the same steps can be dispatched locally with the App Store Connect
API key.
