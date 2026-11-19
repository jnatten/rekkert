# Bug Verification: Americano gives the same partners two rounds running before everyone has partnered everyone

- **Slug**: americano-partner-repeats
- **Tested**: 2026-11-19
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: verified

## Summary

The bug no longer reproduces, measured with the real engine on the same tournament ids before
and after.
- **Your session:** rounds 1–5 of the 18 November session, then drawn by the fix commit
  `710ff397` for 400 tournament ids. Round 6 repeats nobody and rounds 6–9 finish the turn with
  no repeat. The commit before the fix, `6a1a2bb9`, repeats a partner in round 6 for 41 of the
  400 ids (Mattis and Endre again in 9) and somewhere in rounds 6–9 for 204.
- **Other setups:** 1 110 tournaments across seven setups went from 6–35 with back-to-back
  partners and 24–179 with any repeated partner per setup, to 0 and 0.
- **Older builds:** they fold the fix's rounds identically, and the fix folds theirs.
- **Regressions:** none. The full suite passes and both apps build.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction: the 18 Nov session (post-fix) | Fix commit `710ff397` and the commit before it, `6a1a2bb9`, each exported with `jj file show` into `Packages/RekkertKit/.build/verify/`. A release-build test replays rounds 1–5 as played, then draws rounds 6–9 as the store does (`TournamentEngine.sitOuts(for:)`, then `appendingRound`), over 400 tournament ids | pass | Before: round 6 repeats a partner in 41/400 (Mattis+Endre in 9), rounds 6–9 in 204/400. After: 0, 0 and 0. |
| Reproduction: the assessment's simulation (post-fix) | The same probe, one full turn per tournament: 5/1, 6/1 (150 each), 9/2 (400), 10/2 (150), 11/2 (100), 13/3, 14/3 (80 each) | pass | Before: back-to-back partners 6–35 and any repeat 24–179 per setup; 9/2 gave 35 and 179, as in the assessment. After: 0 and 0 in every setup. Sit-outs even and nobody twice running, before and after. |
| Older devices | `scripts/cross-build.sh --new 710ff397 890e0c52 eb775886`, then `--players 10 86ffb741` | pass | 18/18 folds matched in Americano and Mexicano: the current TestFlight build, the oldest CI build and 1.1, redraws on both sides included. Americano repeated no partner within the first turn. |
| New / updated tests | `swift test` (`PartnerTurnTests`, `MixedBenchTests`, `SyncTests.theBenchADrawCarriesLandsOnBothDevices`) | pass | "Nobody partners twice in a turn", "Mixing who sits out together" and "Watch and phone sync" suites all passed. |
| Regression suite | `swift test` in `Packages/RekkertKit` on the committed code (working copy empty) | pass | Core 942/942. Sync 629/629, with 27 known issues, all in the intermittent radio-timing suites (8 players, no bench). |
| Type-check: iOS app | `xcodebuild -scheme Rekkert -destination 'generic/platform=iOS Simulator' build` | pass | `** BUILD SUCCEEDED **` |
| Type-check: watch app, incl. 32-bit | `xcodebuild -scheme RekkertWatch -destination 'generic/platform=watchOS' build` | pass | `** BUILD SUCCEEDED **` |
| Lint | — | not-run | The repo has no SwiftLint/SwiftFormat config. |
| On court, real devices | — | not-run | No session has been played on the new build yet. |
| Apple Watch SE timing | — | not-run | No device. The Mac release worst case is 131 ms (`fix.md`). |

## Output Excerpts

```
VERIFY [6a1a2bb9] 18 Nov rounds 1-5, then drawn, 400 tournament ids: round 6 repeats a partner in 41, last round's partners in 9, mattis+endre again in 9; rounds 6-9 repeat a partner in 204
VERIFY [710ff397] 18 Nov rounds 1-5, then drawn, 400 tournament ids: round 6 repeats a partner in 0, last round's partners in 0, mattis+endre again in 0; rounds 6-9 repeat a partner in 0
VERIFY [6a1a2bb9] 9/2, 9-round turn, 400 tournaments: back-to-back partners in 35, any repeated partner in 179; sat out twice running 0; uneven 0
VERIFY [710ff397] 9/2, 9-round turn, 400 tournaments: back-to-back partners in 0, any repeated partner in 0; sat out twice running 0; uneven 0
VERIFY [6a1a2bb9] 10/2, 11-round turn, 150 tournaments: back-to-back partners in 27, any repeated partner in 142; …
VERIFY [710ff397] 10/2, 11-round turn, 150 tournaments: back-to-back partners in 0, any repeated partner in 0; sat out twice running 0; uneven 0
VERIFY [6a1a2bb9] 14/3, 15-round turn, 80 tournaments: back-to-back partners in 16, any repeated partner in 78; …
VERIFY [710ff397] 14/3, 15-round turn, 80 tournaments: back-to-back partners in 0, any repeated partner in 0; sat out twice running 0; uneven 0
```

```
==> 710ff397 against 890e0c52, 9 players on two courts
XVER [710ff397] recorded americano-A: partners repeated within the first turn 0
XVER [890e0c52] folded americano-A: 15 rounds, 0 differing
…
==> Every fold matched            (also against eb775886, and 86ffb741 with 10 players)
```

```
􁁛  Test run with 942 tests in 85 suites passed after 15.609 seconds.
􀢂  Test run with 629 tests in 105 suites passed after 339.380 seconds with 27 known issues.
** BUILD SUCCEEDED **   (Rekkert, iOS Simulator)
** BUILD SUCCEEDED **   (RekkertWatch, watchOS)
```

## Residual Risks

- **Not yet seen on court.** No session has been played on the new build. The sharing records
  can't show draws until spec 005 T099 (`roundShown`) exists, so the next on-court check needs
  rounds noted by hand again.
- **Apple Watch SE timing** is unmeasured. The worst case on a Mac is 131 ms, right after a
  hand-picked sit-out.
- **When nobody sits out (8, 12, 16 players)** nothing changes, by decision. Partner repeats
  there remain as before.
- **Interventions can break the plan.** A hand-picked sit-out, a round drawn by an older device,
  an added player or a cancelled round can leave no repeat-free completion. The tests bound this
  to no back-to-back partners and at most one repeat in the cases covered.
- **Twice running is allowed when needed.** Partners win over sitting out twice running when the
  fair search can't finish a turn within its budget: 1 in 8 twenty-round turns at 16 players on
  3 courts (`fix.md`).
- **Sit-outs are less evenly spread** in Americano than after `americano-draw-randomness`, by
  decision: shorter gaps and some repeated sit-out pairs. Mexicano is unchanged.
- **Older builds from before 25 September** ignore the carried bench and already disagree.
- **This verification used scratch exports** under `Packages/RekkertKit/.build/verify/`, which
  VCS ignores, and the committed `scripts/cross-build.sh`.

## Recommendation

Close the bug. It is verified end to end with the real engine: on the reported session's rounds,
on the assessment's simulation with the same ids before and after, and against older builds,
with no regressions. Before release, time a 12–16-player draw on an Apple Watch SE. At the next
Americano with someone sitting out, note the rounds and check that nobody partners twice before
everyone has partnered everyone. Add a TestFlight note that Americano now trades a little
sit-out spread for this.
