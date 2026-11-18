# Bug Fix: Americano benches the same players together every rotation

- **Slug**: americano-draw-randomness
- **Fixed**: 2026-11-18
- **Assessment**: ./assessment.md
- **Status**: applied

## Summary

The device that draws an Americano or Mexicano round now picks who sits out with a new rule.
Sit-out counts stay even, and among those equally due the rule mixes who sits out together.
The bench goes in the round event's existing `sitOuts` field, which every build since
25 Sep 2026 obeys, so older phones and watches land on the same round. How a received event is
folded, `Tournament` and `BenchOrder` are unchanged, so logs already recorded replay exactly as
before.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `Packages/RekkertKit/Sources/RekkertCore/Tournament/PairingHistory.swift` | modified | Counts how often each pair has sat out together (`benchedTogether`, `satOutTogether(_:_:)`). |
| `Packages/RekkertKit/Sources/RekkertCore/Tournament/RoundScheduler.swift` | modified | `BenchSpread` cost; `RoundScheduler.mixedBench`, the new rule; public `TournamentEngine.bench(for:picked:redrawing:)` and `TournamentEngine.sitOuts(for:picked:redrawing:)`. `split` and `BenchOrder` are untouched. |
| `Packages/RekkertKit/Sources/RekkertSync/MatchStore.swift` | modified | `nextRound()` and `redrawRound(sittingOut:)` record the bench as `sitOuts` and work out `placed` around it. |
| `App/Sources/Views/SitOutPickerView.swift` | modified | The preview shows the bench the new rule picks, and the footer text no longer says "whoever sat out longest ago". |
| `README.md` | modified | The Americano/Mexicano sit-out paragraph describes the mixing. The winner-court paragraph no longer says it sits out "as in Americano". |
| `Packages/RekkertKit/Tests/RekkertCoreTests/Helpers.swift` | modified | `MatchLog.drawRound` and `redrawRound` mirror the store again; new `drawRoundAsOlderBuild`. |
| `Packages/RekkertKit/Tests/RekkertCoreTests/MixedBenchTests.swift` | added test | 13 tests (24 cases). See below. |
| `Packages/RekkertKit/Tests/RekkertSyncTests/SyncTests.swift` | added test | `theBenchADrawCarriesLandsOnBothDevices` |

## Diff Highlights

The store only adds the bench to what it already records:

```swift
let sitOuts = TournamentEngine.sitOuts(for: tournament)
record(.nextRound(
    after: tournament.rounds.count - 1,
    at: Date(),
    sitOuts: sitOuts,
    placed: TournamentEngine.placement(of: tournament, sitOuts: sitOuts)
))
```

`TournamentEngine.sitOuts(for:)` returns nil whenever the new bench is the one the event would
draw anyway. That covers the whole first rotation and about 40–70 % of later rounds,
depending on the setup. Those events are byte-for-byte what they were.

`RoundScheduler.mixedBench`:
- Keeps `(chosen, sit-outs)` as the leading key.
- Walks the equally-due benches in the seeded order.
- Scores each bench by (rounds short of `max(2, rotation − 1)`, times its pairs sat out
  together), adding the best bench the round after would leave.
- Is capped at a fixed amount of work (200 000 units, a bench of *b* costing *b(b+1)/2*), the
  same on every device.
- Falls back to the bench `.longestRested` would draw whenever that scores strictly better
  than everything the search reached.

## Tests Added or Updated

`MixedBenchTests.swift` ("Mixing who sits out together"):
- `tenPlayersNeverSitOutWithTheSamePlayerTwice`: 10 players, 2 courts, 15 rounds. 15 different
  bench pairs, every gap ≥ 4, sit-outs even after every round.
- `theSamePairsNoLongerComeRoundEveryRotation`: the old queue repeats every 5 rounds. The new
  draw matches it for the first rotation, then differs.
- `sitOutsStayEvenAndSpreadOut(players:courts:rounds:)`: 8 setups (5/1, 6/1, 9/2, 10/2, 11/2,
  12/2, 13/2, 14/3) × 8 seeds. Even after every round, and every gap ≥ `max(2, rotation − 1)`.
- `pairsDoNotRepeatWhileFreshOnesAreLeft`: 10/2 and 14/3 × 8 seeds, no repeated bench pair.
- `aBenchOfOneVariesItsOrder`: 5 players, 1 court. The order changes between rotations for all
  8 seeds, and every gap ≥ 4.
- `theFirstRotationCarriesNoBench(format:)`: Americano and Mexicano carry no `sitOuts` for
  rounds 1–5.
- `anOlderBuildFollowsTheBenchTheDrawCarries(format:)`: every draw is re-encoded in the older
  event shape (`after`, `at`, `sitOuts`, no `placed`) and decoded. Americano and Mexicano fold
  to the identical tournament.
- `aRoundAnOlderBuildDrawsIsFollowedAndTheMixingCarriesOn`: an older-build draw in round 8
  comes out as the old rule draws it. Later rounds stay even, with no back-to-back sit-outs.
- `roundsPlayedBeforeTheUpdateStayAsTheyWere`: 8 rounds drawn the old way, then 7 the new way.
  The first 8 rounds are unchanged.
- `aRedrawKeepsThePickAndMixesTheRest`: the picked player sits out and the rest is
  `bench(for:)`'s pick. An older build folding the same event draws the same round.
- `aMexicanoIsStillDrawnFromTheTableAroundTheMixedBench`: each round equals the table draw
  around its bench. No repeated pairs, even sit-outs.
- `aLadderDrawsItsBenchAsItAlwaysHas(partners:)`: winner court, fixed and split partners.
  `sitOuts(for:)` is nil, and `bench(for:)` is the ladder's own bench.
- `twoDevicesDrawingAtOnceMakeOneRound`: two events for the same round with the same bench
  give one round, identical to a single draw.

`SyncTests.swift` (`theBenchADrawCarriesLandsOnBothDevices`): a phone and a watch take turns
drawing 15 rounds. Both end in the same state, with 15 different pairs sitting out.

No existing test needed changing. `theBenchComesRoundInTheOrderItFirstWent`, the
`SeededDrawTests` pins and `aTournamentBegunBeforeTheTieBreakKeepsItsDraws` all still pass:
they draw through the engine directly, which still draws with the stored order.

## Local Verification

- `swift test` in `Packages/RekkertKit`:
  - RekkertCoreTests: 934 tests in 84 suites passed.
  - RekkertSyncTests: 629 tests in 105 suites passed, with 38 known issues. All of them are
    the intermittent `withKnownIssue` radio-timing checks in "A club night", "Points within a
    second in a busy hall" and "Fitting the simulated radio to a record". Those play 8 players
    with no bench. The count varies from run to run (25 on the first full run).
- `tuist generate --no-open`, then
  `xcodebuild -workspace Rekkert.xcworkspace -scheme Rekkert -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
  → **BUILD SUCCEEDED**. The generated project was stale before regenerating.
- Release-build measurements on a scratch copy outside the repo, on a Mac, using the public API
  only.

  Draw quality, 40 seeds per row:

  | Players / courts | Repeated bench pairs: old queue → new | Back-to-back | Shortest gap: old → new | Uneven |
  |---|---|---|---|---|
  | 5 / 1 | 0 % → 0 % | 0 | 5 → 4 | 0 |
  | 6 / 1 | 75.0 % → 1.2 % | 0 | 3 → 2 | 0 |
  | 9 / 2 | 0 % → 0 % | 0 | 9 → 8 | 0 |
  | 10 / 2 | 66.7 % → **0 %** | 0 | 5 → 4 | 0 |
  | 11 / 2 | 31.6 % → 17.2 % | 0 | 3 → 3 | 0 |
  | 12 / 2 | 75.0 % → 26.9 % | 0 | 3 → 2 | 0 |
  | 13 / 2 | 46.8 % → 42.9 % | 0 | 2 → 2 | 0 |
  | 14 / 3 | 66.7 % → **0 %** | 0 | 7 → 6 | 0 |
  | 16 / 3 | 66.7 % → 20.8 % | 0 | 4 → 3 | 0 |
  | 20 / 3 | 51.2 % → 49.3 % | 0 | 2 → 2 | 0 |

  Time per draw, `TournamentEngine.sitOuts(for:)`:

  | Players / courts | Average | Worst |
  |---|---|---|
  | 10 / 2 | 0.3 ms | 0.4 ms |
  | 12 / 2 | 4 ms | 31 ms |
  | 16 / 3 | 8 ms | 34 ms |
  | 24 / 4 | 58 ms | 137 ms |
  | 30 / 2 | 35 ms | 62 ms |

## Deviations from Assessment

- **The search cap counts work, not benches tried.** A cap on the number of benches let a
  30-player, 2-court draw take about 1 s on a Mac. Each bench now costs *b(b+1)/2*, which keeps
  every setup measured under about 140 ms.
- **The bench `.longestRested` would draw is a fallback.** With the work cap, the first
  version let big benches (13/2, 16/3, 20/3) sit people out two rounds running when the search
  was cut off: 375 times over 40 seeds at 20/3. The bench `.longestRested` draws is now always
  scored, and it wins whenever it beats everything the search reached. Ties still go to the
  seeded order, so a bench of one keeps varying. Back-to-back sit-outs are now 0 in every setup
  measured.
- **The lookahead orders next-round candidates longest-rested first**, so a cut-off lookahead
  lands on the best next bench sooner.
- **`SitOutPickerView`'s preview logic changed too, not only its text.** Otherwise the picker
  would show a bench different from the one the redraw records.
- **`Helpers.swift` changed (scope expansion).** `MatchLog.drawRound`/`redrawRound` say they
  mirror `MatchStore`, so they were updated, and `drawRoundAsOlderBuild` was added.
- **Older-device tests are core tests, not `actsAsOlderBuild` sync tests.**
  `actsAsOlderBuild` changes the protocol and clock a store advertises, not how it draws or
  folds. The core tests instead decode every draw in the older event shape, and record
  older-build draws without `sitOuts`. The sync test covers a phone and a watch both drawing.
- **"Two taps at once" is a reducer-level test**: two events for the same round, rather than
  two live stores racing.

## Follow-ups

- **Measure on an Apple Watch SE (1st generation).** A watch that draws runs the search. Club
  sizes are a few ms on a Mac, and the slowest setup measured is about 140 ms.
- **Evening out opponents** is the agreed follow-up; see assessment, Teams and opponents.
- **Mention the change in the TestFlight / release notes:** who sits out together now changes
  from rotation to rotation in Americano and Mexicano.
- **Friendly mode** still uses `.fewestSitOuts` and can bench someone two rounds running. It
  was out of scope here.
- **Two devices drawing at once with different histories** (for example a cancel racing the
  draw) can change the round once, the same way on every device. This is a known consequence
  of carrying `sitOuts` and is noted in the assessment.
