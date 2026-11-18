# Bug Verification: Americano benches the same players together every rotation

- **Slug**: americano-draw-randomness
- **Tested**: 2026-11-18
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

The bug no longer reproduces. The assessment's case is 10 players, 2 courts, tournament id
`…00FF`. Driven through `MatchStore.nextRound()`, the call the app's draw button makes, it
now benches 15 different pairs in 15 rounds, where before the same 5 pairs came round every
5 rounds. Mexicano behaves the same. The pre-fix code, built from the parent commit
`890e0c52`, folds logs recorded by the fixed code to identical states, and the reverse holds
too, including a redraw and a round the old code drew itself. The full package suite passes,
and the iOS and watch apps build.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | Scratch copy of the fixed package: `MatchStore.configure` + `nextRound()` ×15, Americano and Mexicano, 10 players, 2 courts, id `…00FF`; Americano redrawn with one player picked in round 10 | pass | Rounds 1–5 equal the assessment's (P1 P7, P3 P6, P0 P5, P4 P9, P2 P8). Round 6 onwards differs: 0 repeated pairs over 15 rounds in both formats. |
| Older build follows newer draws | Pre-fix package (`jj file show -r @-`) folds the fixed build's logs (`SessionReducer.state`) and compares them with the state the fixed build recorded | pass | `americano-A` and `mexicano-A` equal, redraw event included. |
| Newer build follows an older draw | The pre-fix `MatchStore` draws round 16 onto that log. The fixed build folds it, then draws rounds 17–21. | pass | `americano-B` and `mexicano-B` equal. |
| Older build follows again | The pre-fix build folds the 21-round log | pass | `americano-C` and `mexicano-C` equal. |
| New tests | `swift test` (`MixedBenchTests`, `theBenchADrawCarriesLandsOnBothDevices`) | pass | 13 tests / 24 cases plus the sync test |
| Regression suite | `swift test` in `Packages/RekkertKit` | pass | Core 934/934, Sync 629/629. 27 known issues, all intermittent `withKnownIssue` radio-timing checks (8 players, no bench). |
| iOS build (type-check) | `xcodebuild -scheme Rekkert -destination 'generic/platform=iOS Simulator' build` | pass | `** BUILD SUCCEEDED **` |
| watchOS build, incl. 32-bit SE | `xcodebuild -scheme RekkertWatch -destination 'generic/platform=watchOS' build` | pass | Built for `arm64` and `arm64_32`. |
| Draw quality and speed | Release build on a scratch copy identical to `Sources/`, 40 seeds per setup | pass | Matches `fix.md`. See excerpts. |
| Lint | — | not-run | The repo has no SwiftLint/SwiftFormat config. |
| In-app UI (simulator taps) | — | skipped | The store path the button calls was exercised instead. The picker preview change was type-checked by the app build only. |
| Apple Watch SE hardware | — | not-run | No device available. 32-bit compiled only. |

## Output Excerpts

Reproduction through the store, Americano. Round 10 is the redraw with one player picked:

```
REPRO americano round 1: bench ["P1", "P7"]      round 6: bench ["P1", "P6"]     round 11: bench ["P1", "P2"]
REPRO americano round 2: bench ["P3", "P6"]      round 7: bench ["P0", "P7"]     round 12: bench ["P5", "P6"]
REPRO americano round 3: bench ["P0", "P5"]      round 8: bench ["P4", "P5"]     round 13: bench ["P4", "P7"]
REPRO americano round 4: bench ["P4", "P9"]      round 9: bench ["P8", "P9"]     round 14: bench ["P3", "P8"]
REPRO americano round 5: bench ["P2", "P8"]      round 10: bench ["P0", "P3"]    round 15: bench ["P2", "P9"]
REPRO americano repeated bench pairs over 15 rounds: 0
REPRO mexicano repeated bench pairs over 15 rounds: 0
```

Handoff between the pre-fix and fixed builds:

```
XVER americano-A folded here == written there: true      (old build)
XVER mexicano-A folded here == written there: true       (old build)
XVER americano older build drew round 16, bench ["P0", "P1"]
XVER americano-B folded here == written there: true      (new build)
XVER mexicano-B folded here == written there: true       (new build)
XVER americano after newer draws 17-21: 21 rounds, repeated bench pairs 1
XVER mexicano after newer draws 17-21: 21 rounds, repeated bench pairs 2
XVER americano-C folded here == written there: true      (old build)
XVER mexicano-C folded here == written there: true       (old build)
```

Over 21 rounds with one old-build draw in the middle, 1 (Americano) and 2 (Mexicano)
repeated pairs remain. Mexicano's round 16, drawn the old way, repeats round 11's P0 P1. The
assessment expected this: rounds an older device draws bench the old way.

Test suite:

```
􀢂  Test run with 629 tests in 105 suites passed after 350.688 seconds with 27 known issues.
􁁛  Test run with 934 tests in 84 suites passed after 4.818 seconds.
```

Release build, 40 seeds per setup:

```
QUALITY 10/2 queue repeated pairs  66.7%  back-to-back   0  worst gap 5  uneven 0
QUALITY 10/2 mixed repeated pairs   0.0%  back-to-back   0  worst gap 4  uneven 0
QUALITY 14/3 mixed repeated pairs   0.0%  back-to-back   0  worst gap 6  uneven 0
QUALITY  6/1 mixed repeated pairs   1.2%  back-to-back   0  worst gap 2  uneven 0
QUALITY 20/3 mixed repeated pairs  49.3%  back-to-back   0  worst gap 2  uneven 0
TIMING 10 players 2 courts bench  2: avg    0.27 ms  worst    1.07 ms
TIMING 16 players 3 courts bench  4: avg    8.46 ms  worst   31.71 ms
TIMING 24 players 4 courts bench  8: avg   58.83 ms  worst  141.63 ms
```

Back-to-back sit-outs and uneven counts were 0 in all 10 setups.

## Residual Risks

- **Not timed on an Apple Watch SE.** Timing was measured on a Mac only. A watch that draws
  runs the search; club sizes take ≤ 35 ms on the Mac, and the slowest setup measured is
  ~140 ms.
- **32-bit execution not run.** The `arm64_32` build compiles but was not executed. The new
  code draws only through `SeededGenerator` (`UInt64`), uses no dictionary iteration order,
  and its `Int` values stay far below 2³¹ (budget 200 000), so it should draw the same on
  32 and 64 bits. That is from reading the code, not from running it.
- **Older-device compatibility was checked by folding logs, not over a live radio link.** Both
  directions used the real pre-fix code, but not two physical devices on different builds.
- **Builds from before 25 Sep 2026** ignore `sitOuts` and already disagreed with current
  builds after the first rotation. Not tested; unchanged by this fix.
- **Two devices drawing the same round at once** from different histories can change that
  round once, the same way everywhere. Covered for identical histories only.
- **The sit-out picker's preview** was compiled but not exercised in the UI.

## Recommendation

Close the bug. Verified end to end at the store level: the assessment's reproduction no
longer shows repeating sit-out pairs, the regression suite is green, and the pre-fix code
replays logs from the fixed code identically (and the reverse). Before release, time a
12–16-player draw on an Apple Watch SE (1st generation), and check that the picker preview
matches the redraw it records.

## Extra verification: older devices (2026-11-18)

Run against the builds testers and App Store users can actually have. The CI TestFlight runs
from 28 Sep to 17 Nov give 20 builds, which hold 8 distinct versions of the draw and fold code
(`RekkertCore/Tournament/**`, `SessionReducer`, `MatchEvent`, `MatchLog`, and
`MatchStore.nextRound`/`redrawRound`). Build 50 (`f55d3630`, 22 Sep) stands in for the
manually uploaded 1.0 builds that predate the sit-out field; TestFlight keeps those until about
mid-December. Each build was exported from its commit with `jj file show` and run in a scratch
copy. The fixed build is `358d7a27`.

| Check | Builds | Result |
|-------|--------|--------|
| **Log handoff**: fixed records 15 rounds (redraw in round 10) → old folds, draws round 16 and redraws it → fixed folds, draws 17–21 and redraws → old folds | `890e0c52`, `14f7a2c9` (1.2), `576fb358`, `86ffb741`, `bb79ccac`, `c51a2cab`, `1125959d`, `eb775886` (oldest CI) | pass. 0 differing rounds at every fold, Americano and Mexicano. The whole decoded `SessionState` was equal each time. |
| **Pre-field build**: build 50 folds the fixed log | `f55d3630` | Differs from round 6 (9/15 Americano, 10/15 Mexicano). It differs just as much from today's `main` (10/15 each). This build already disagreed with `main`, and the fix doesn't make it worse. |
| **Live sync over the real protocol**: two processes, each a real `MatchStore` whose loopback end is bridged through files (live sends with replies, queue, snapshots). New draws 1–8 and redraws, old draws 9–10 and redraws, new draws 11, then both tap at once for rounds 12–16. | `890e0c52`, `86ffb741`, `eb775886`; Americano and Mexicano | pass, 6/6. Identical event sets and rounds on both sides, with two draw events per raced round, including races where the fixed build carried a bench and the old one didn't. |
| **Determinism across processes**: the same tournament recorded in 3 processes, each with its own hash seed | fixed | pass. Identical draws and identical carried benches, order included, in 16 draw events per format, 7 carrying a bench. |

- **32-bit watch:** still not run on hardware. Code review of the new path finds no
  `Int`-width dependence:
  - every random draw goes through `SeededGenerator` (`UInt64`);
  - sorts use a total order with an index tiebreak;
  - there is no dictionary or set iteration;
  - all `Int` values stay below 2³¹ (the budget is 200 000, and the `Int.max` sentinel is
    overwritten before any arithmetic).
- **Harness note:** in one Mexicano live run, a side saw the other's draw before tapping and
  drew an extra round, giving 18 rounds instead of 16. Both sides still held identical logs.
  That is the test's timing, not a disagreement.
