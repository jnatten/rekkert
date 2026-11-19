# Bug Fix: Americano gives the same partners two rounds running before everyone has partnered everyone

- **Slug**: americano-partner-repeats
- **Fixed**: 2026-11-19
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

Americano now plans who sits out for the rest of the turn, so that the unchanged team search
pairs nobody twice before everyone has partnered everyone. This applies wherever somebody sits
out. The bench goes out in the round event's `sitOuts`, as before. Every installed build since
25 September takes the bench from there and works out the same teams with the same search, so
older phones and watches agree on every round. Sit-outs stay even, and nobody sits out two rounds
running unless that is the only way to keep the partners fresh.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Packages/RekkertKit/Sources/RekkertCore/Tournament/RoundScheduler.swift` | modified | New `RoundScheduler.plannedTurn`, the turn planner. `TournamentEngine.bench(for:)` uses it for Americano. Mexicano keeps `mixedBench`, and `PairingSearch` is untouched. |
| `Packages/RekkertKit/Sources/RekkertCore/Tournament/PairingHistory.swift` | modified | Records which pairs partnered in the last round played (`lastPartners`, `partneredLastRound`). |
| `Packages/RekkertKit/Tests/RekkertCoreTests/PartnerTurnTests.swift` | added test | 8 tests, 22 cases. See below. |
| `Packages/RekkertKit/Tests/RekkertCoreTests/MixedBenchTests.swift` | updated test | The sit-out spread checks now run on Mexicano, which keeps them. Americano is checked for even sit-outs and nobody twice running. |
| `Packages/RekkertKit/Tests/RekkertSyncTests/SyncTests.swift` | updated test | `theBenchADrawCarriesLandsOnBothDevices` now checks no repeated partner in the 11-round turn and nobody sitting out twice running, on both devices. |
| `README.md` | modified | The Americano paragraph: what the draw promises about partners and sit-outs, and that older versions draw the same teams. A full rotation with sit-outs ends in the fewest rounds possible. |
| `App/Sources/Views/SitOutPickerView.swift` | modified | Footer text for how open sit-out places are filled. |
| `scripts/cross-build.sh`, `scripts/cross-build/CrossBuild.swift` | added | Cross-build check, as the assessment asked. It exports any build since 25 September with `jj` into `Packages/RekkertKit/.build/` and passes a tournament log back and forth with the new build, in both formats. |

## Diff Highlights

How `plannedTurn` chooses, in outline (`RoundScheduler.swift`, doc comment on the function):

- **Turn and cap.** `cap` = the lowest partner count among today's pairs + 1. The turn
  (`horizon`) is as many rounds as the pairs under the cap can fill. In the first turn that
  means no repeats at all. Afterwards nobody partners a third time before everyone has twice.
- **Draw order for future rounds.** `SeededGenerator(id, salt: round)`, shuffled. This is the
  order every build uses for that round, and it doesn't depend on history.
- **Candidates.** The benches `forEachBench` allows, keeping fewest sit-outs first. They are
  tried in today's sit-out order: nobody sitting out twice running, then `BenchSpread`, then the
  seeded order. At most 300 per round.
- **Each candidate's teams** come from `PairingSearch.teams(from: order − bench, …)`, exactly
  what every build will draw. A candidate is pruned if any pair would reach the cap or partner
  last round's partner again.
- **Depth-first search.** First with nobody sitting out twice running (budget 200 000 units).
  If that finds no whole turn, a second search allows it (100 000), because partners win. If
  neither finds a whole turn, it keeps the plan that got furthest.
- **Fallback with no plan at all** (50 000). The bench whose teams have the fewest, in order:
  back-to-back partners, partnerships over the cap, people sitting out twice running, then
  partner repeats overall.
- **Fixed budgets.** Weighing a bench costs b(b+1)/2 units and drawing its teams courts² × 100,
  so the search stops at the same point on every device.

## Tests Added or Updated

`PartnerTurnTests.swift` ("Nobody partners twice in a turn"):
- `roundSixOfEighteenNovemberRepeatsNobody(seed:)`: rounds 1–5 of the 18 November session as
  played, 12 tournament ids. Round 6 repeats nobody, rounds 6–9 finish the turn with nobody
  twice, sit-outs even, nobody twice running.
- `aFullTurnRepeatsNobody(players:courts:)`: 5/1, 6/1, 9/2, 10/2, 11/2, 13/3, 14/3, 6 ids each.
  No repeated partner in the turn, even sit-outs, nobody twice running.
- `aFullRotationEndsAsSoonAsThePartnershipsAllow(players:courts:)`: the same setups. Everyone
  has partnered everyone after ⌈pairs ÷ partnerships per round⌉ rounds.
- `drawingRoundByRoundFollowsThePlanMadeAtTheStart`: 10/2. Re-planning every round reproduces
  the plan made at round 1, all 11 rounds.
- `pastTheTurnNobodyPartnersAThirdTimeEarly(players:courts:backToBackAllowed:)`: two turns at
  9/2, 10/2 and 6/1. Nobody partners a third time. No back-to-back partners at 9/2 and 10/2;
  at most one at 6/1, where at that point every bench had one.
- `aHandPickedSitOutIsKeptAndTheTurnCarriesOn`: 9/2 with a pick in round 4. The pick stands, no
  back-to-back partners, at most one repeat.
- `aRoundAnOlderBuildDrewIsFollowedAndPlanningCarriesOn`: 9/2 with round 5 drawn without
  `sitOuts`, as an older build draws it. No back-to-back partners, at most one repeat.
- `withNobodySittingOutTheDrawIsAsItWas`: 8/2. No bench carried, the draw unchanged.

Also updated:
- **`MixedBenchTests`:**
  - `tenPlayersNeverSitOutWithTheSamePlayerTwice`, `sitOutsStayEvenAndSpreadOut` and
    `pairsDoNotRepeatWhileFreshOnesAreLeft` now run on Mexicano; `sitOutsStayEvenAndSpreadOut`
    also checks Americano's guarantees.
  - `anOlderBuildFollowsTheBenchTheDrawCarries` and the rest still pass as they were.
    `anOlderBuildFollowsTheBenchTheDrawCarries` now exercises the planner: every draw
    re-encoded in the older event shape folds to the same tournament.
- **`SyncTests.theBenchADrawCarriesLandsOnBothDevices`:** see Changes.

## Local Verification

- **`swift test` (`Packages/RekkertKit`):** RekkertCoreTests 942 / 942 passed. RekkertSyncTests
  629 / 629 passed, with 25 known issues. All of them are the intermittent `withKnownIssue`
  radio-timing checks ("A club night", "Points within a second in a busy hall", "Fitting the
  simulated radio"), which play 8 players with no bench.
- **`xcodebuild`, scheme `Rekkert`, `generic/platform=iOS Simulator`:** BUILD SUCCEEDED.
- **`xcodebuild`, scheme `RekkertWatch`, `generic/platform=watchOS`:** BUILD SUCCEEDED, arm64
  and arm64_32.
- **`scripts/cross-build.sh`** against the 8 distinct draw-code versions among installed builds
  (`890e0c52`, `14f7a2c9`, `576fb358`, `86ffb741`, `bb79ccac`, `c51a2cab`, `1125959d`,
  `eb775886`): every fold matched (48 / 48, Americano and Mexicano), redraws on both sides
  included. Americano repeated no partner within the first turn in any run.
- **Release timing** on a Mac, `TournamentEngine.sitOuts(for:)`, 4 tournaments per row, with a
  hand-picked sit-out in round 4. The probe test was temporary and removed.

  | Players / courts (out) | Average | Worst |
  |---|---|---|
  | 9 / 2 (1) | 5.6 ms | 131 ms |
  | 10 / 2 (2) | 2.6 ms | 6.7 ms |
  | 11 / 2 (3) | 3.7 ms | 15 ms |
  | 12 / 2 (4) | 9.6 ms | 26 ms |
  | 13 / 2 (5) | 12.5 ms | 75 ms |
  | 13 / 3 (1) | 7.8 ms | 20 ms |
  | 14 / 3 (2) | 19 ms | 71 ms |
  | 16 / 3 (4) | 20 ms | 67 ms |
  | 20 / 3 (8) | 26 ms | 49 ms |
  | 24 / 4 (8) | 41 ms | 73 ms |
  | 20 / 1 (16) | 17 ms | 29 ms |
  | 30 / 2 (22) | 16 ms | 28 ms |

  The worst case is the round after a hand-pick, when no whole turn exists and every pass
  spends its budget.
- **Whole turns, 8 tournaments each:**

  | Players / courts | Turn | Repeated partners | Sat out twice running | Uneven sit-outs |
  |---|---|---|---|---|
  | 11 / 2 | 13 rounds | 0 | 0 | 0 |
  | 12 / 2 | 16 rounds | 0 | 0 | 0 |
  | 13 / 2 | 19 rounds | 0 | 0 | 0 |
  | 14 / 3 | 15 rounds | 0 | 0 | 0 |
  | 16 / 3 | 20 rounds | 0 | 1 | 0 |

## Deviations from Assessment

- **After the first turn:** the assessment left this open. Implemented the default proposed on
  2026-11-19: nobody partners a third time before everyone has twice, and never last round's
  partner where any bench avoids it. The cap is the lowest partner count + 1, and the turn is
  as many rounds as the pairs under the cap can fill.
- **"Nobody twice running" is a first pass, not an absolute.** The assessment's feasibility runs
  kept it hard. Here, after "partners win no matter what", a second pass may allow it when the
  fair pass finds no whole turn within its budget.
  - **With the first budget of 100 000:** twice-running sit-outs at 13/2 and 16/3 (2 each in 8
    turns).
  - **With 4×:** none, so they come from the budget, not from need.
  - **Settled on 200 000:** 0 at 13/2, 1 in 8 turns at 16/3.
  - **Tried and dropped:** preferring the fair pass's partial plan led to repeated partners at
    16/3. Fewer candidates per round further ahead did the same.
- **The budget counts work, not team draws.** A cap of 1 500 team draws let large benches take
  0.7–10 s per draw on a Mac (20–30 players). Now every candidate weighed and every team draw
  is charged, with at most 300 candidates per round.
- **Fallback order:** back-to-back partners, partnerships over the cap, sitting out twice running,
  partner repeats overall, then sit-out order. The assessment listed only the first two and
  today's sit-out order.
- **Scope expansions:**
  - `SyncTests.swift`, whose expectation came from `americano-draw-randomness`.
  - The README's full-rotation sentence, which promised extra rounds the planner no longer
    needs.
  - The cross-build script is the log handoff only. The live two-process bridge from
    `americano-draw-randomness` was not rebuilt or rerun. The transport and the event's shape
    are unchanged; only which bench the event carries is new.

## Follow-ups

- **Time a 12–16-player draw on an Apple Watch SE (1st generation).** The worst case on a Mac
  is 131 ms, right after a hand-picked sit-out.
- **Setups where nobody sits out (8, 12, 16 players) are unchanged by decision.** 12/3 repeats
  a partner within a turn in about half of tournaments; revisit with the two-step route in the
  assessment.
- **Opponents** are not part of the plan. Measure their spread, which was the earlier deferred
  follow-up.
- **Friendlies** with 5–6 players use the same team search on one court. Out of scope.
- **TestFlight notes:**
  - In Americano nobody gets the same partner twice in a turn wherever somebody sits out.
  - Sit-outs may now be a little less evenly spread to make that work.
- **Spec 005 T099** (`roundShown(n; digest)` in the sharing record) would let the next on-court
  report be checked from the records.
- **`scripts/verify.sh`** could run `scripts/cross-build.sh` against the latest TestFlight build.
