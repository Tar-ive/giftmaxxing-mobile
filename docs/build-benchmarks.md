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

Commit `4cc28c7`. 20 files moved into `Packages/GiftmaxxingKit`; the app target keeps the rest.
Identical protocol, same machine, same session.

| # | Metric | Runs | Median | vs baseline |
|---|---|---|---|---|
| 1 | Clean build | 59.4 / 57.7 | **58.6s** | 🔴 +6.5% slower |
| 2 | Incremental — view file | 9.9 / 8.9 / 10.0 | **9.9s** | 🔴 +15% slower |
| 3 | Incremental — model file (now in the package) | 7.3 / 4.3 / 3.6 | **4.3s** | 🟢 **47% faster** |
| 4 | Incremental — ranker file (now in the package) | 3.6 / 3.5 / 3.1 | **3.5s** | 🟢 **55% faster** |
| 5 | App test cycle | 58.4 / 47.4 | **52.9s** | 🔴 +8% slower |
| 6 | Module-only tests (`swift test`) | 4.5 / 0.9 / 0.8 | **0.9s** | 🟢 **54× faster than #5** |

### What actually happened

**The prediction was half wrong, in the useful direction.** The baseline showed all incremental
builds at ~8s and I concluded the module boundary had little left to save. It saved a lot: touching a
model now costs 4.3s instead of 8.1s, and touching a ranker 3.5s instead of 7.7s, because the package
target and the app target compile separately rather than the app module recompiling as one unit.

**The costs are real but small.** A clean build is ~3.6s slower and app-only work is ~1.3s slower —
the price of an extra module boundary and package resolution. Anyone editing views all day pays it.

**Metric 6 is the headline.** The ranking logic — the part with the most test coverage and the most
subtle failure modes — now runs its 41 tests in **0.9 seconds** with no simulator, against 52.9s for
the app suite. That is a different kind of loop: you can run it on every save.

### What this says about extracting modules 3 and 4

Do it, but for the right reason. The pattern pays when the moved code is (a) frequently edited and
(b) heavily tested — Networking qualifies on both, DesignSystem mainly on (a). Nobody should expect a
faster clean build; expect a faster inner loop on the code you touch most, and a test suite you'll
actually run.
