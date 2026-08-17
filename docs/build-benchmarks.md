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

## Final — all four modules extracted

Commit `aaf54a2`. `Packages/GiftmaxxingKit` holds Core, Recommendation, Networking and DesignSystem
(46 files); the app target is 114 files of views and stores.

| # | Metric | Baseline | After 2 modules | **After 4** | vs baseline |
|---|---|---|---|---|---|
| 1 | Clean build | 55.0s | 58.6s | **68.4s** | 🔴 **+24% slower** |
| 2 | Incremental — view file | 8.6s | 9.9s | **9.9s** | 🔴 +15% |
| 3 | Incremental — Core model | 8.1s | 4.3s | **3.6s** | 🟢 **56% faster** |
| 4 | Incremental — ranker | 7.7s | 3.5s | **3.0s** | 🟢 **61% faster** |
| 5 | App test cycle | 48.9s | 52.9s | **52.8s** | 🔴 +8% |
| 6 | Module tests (`swift test`) | — | 0.9s | **0.8s** | 🟢 60× vs #5 |
| 7 | Incremental — design token (`Theme.swift`) | 8.6s¹ | — | **4.7s** | 🟢 45% faster |
| 8 | Incremental — `APIClient.swift` | 8.6s¹ | — | **4.3s** | 🟢 50% faster |

¹ These files were in the app target at baseline, so metric 2 (~8.6s for any app file) is their
comparable starting point.

### The honest summary

**Everything you edit often got roughly twice as fast; the clean build got a quarter slower.**
Editing a model, a ranker, a design token or the API client now costs 3–5 seconds instead of 8, and
that's the loop you're in all day. Editing a *view* — still the largest share of the code — got
slightly worse, and a from-scratch build went 55s → 68s because there are now five compilation units
to schedule instead of one.

That trade is worth it here: clean builds happen a few times a day, incremental builds happen
constantly, and the 0.8-second `swift test` loop over the ranking, model and networking code is a
different category of feedback than a 53-second simulator run.

**Where the remaining win is.** Views are 60% of the app target and still rebuild as one unit. The
next boundary worth drawing isn't another shared module — it's splitting the *feature* surfaces
(Feed, Swipe, Circles) so a change to one doesn't recompile the others. That's a bigger design
question than moving leaf utilities, and it should wait until someone is actually slowed down by
metric 2.

### What the extraction cost, beyond time

Three problems only surfaced because a module boundary forced them into the open — and all three
were real bugs in waiting, not refactor noise:

1. **`Font.caption` shadowed SwiftUI's.** Inside one module ours won silently. Across the boundary
   it was ambiguous, and the resolution that compiled would have used SwiftUI's dynamic caption at 89
   call sites. Renamed `captionMedium`.
2. **`InteractionQueue` reached for `APIClient.shared`**, tying ranking to networking. Now a protocol
   in Core that the app injects.
3. **Three view bodies stopped type-checking in reasonable time.** Cross-module inference is more
   expensive; the bodies were already too big to be safe.
