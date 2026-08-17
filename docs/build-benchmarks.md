# Build benchmarks

Measured to judge whether extracting Swift modules actually pays for itself. Protocol: Xcode closed,
on power, dedicated `-derivedDataPath /tmp/gm-bench-dd`, median of the runs shown.

**Machine:** MacBook Pro (arm64, Darwin 25.5.0) · **Xcode:** 26.3 (17C529)

## Baseline — before any module extraction

Commit `9bae29a`, tag `pre-modules`. Single app target: 152 Swift files, 37,524 lines.

| # | Metric | Runs | Median |
|---|---|---|---|
| 1 | Clean build (Debug, simulator) | 57.7 / 52.3 | **55.0s** |
| 2 | Incremental — touched `Views/Feed/FeedView.swift` | 12.4 / 8.6 / 8.1 | **8.6s** |
| 3 | Incremental — touched `Models/Post.swift` | 8.2 / 8.1 / 7.6 | **8.1s** |
| 4 | Incremental — touched `Services/Recommendation/OnDeviceRanker.swift` | 7.7 / 7.7 / 7.6 | **7.7s** |
| 5 | Test cycle (`-only-testing:GiftmaxxingTests`, 97 tests) | 53.1 / 44.6 | **48.9s** |
| 6 | Module-only tests (`swift test`) | — | n/a before extraction |

### What the baseline already tells us

**The build-time case for modularization is weak here, and the numbers say so before the work
starts.** Metrics 2, 3 and 4 are all ~8 seconds. Touching a model that 16 files construct costs the
same as touching one leaf view — Swift's incremental compiler is already only rebuilding what
changed plus its dependents, so moving those files behind a module boundary has little left to save.
A 55-second clean build is also not a number anyone is suffering under.

The plan predicted metrics 3 and 4 "should improve … the gain may be small". The baseline says the
gain will be *very* small, so the honest justification for Part 1 is the other three:

- **Metric 5 is the real target.** 48.9s to run 97 tests, because every run compiles 78 view files
  and boots a simulator first. `swift test` on a package with no UI should be a different order of
  magnitude — that is the number to watch after extraction.
- **Boundaries, not speed.** A module the app cannot reach into is what stops two agents editing the
  same 500-line file, which cost 23 conflict hunks this month.
- **Testability.** `InteractionQueue` becomes injectable rather than reaching for `APIClient.shared`.

If metric 6 doesn't land dramatically better than metric 5, that is a genuine argument against
extracting modules 3 and 4.

## After — Core + Recommendation extracted

_Pending: re-run the identical protocol once `Packages/GiftmaxxingKit` is in place._

| # | Metric | Runs | Median | vs baseline |
|---|---|---|---|---|
| 1 | Clean build | | | |
| 2 | Incremental — view file | | | |
| 3 | Incremental — model file (now in the package) | | | |
| 4 | Incremental — ranker file (now in the package) | | | |
| 5 | App test cycle | | | |
| 6 | Module-only tests | | | |
