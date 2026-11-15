# Bug Verification: The host marks guests out of reach between points, though their links are up

- **Slug**: host-loses-quiet-guests
- **Tested**: 2026-11-15
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

In the court harness, with phones in a bag as on 14 November, the bug reproduces without the fix and is gone with it. `scripts/verify.sh` passes on the fix commit (`1c93288c`). The result is partial, not verified, because the reproduction the assessment lists on real devices has not been run. The bug was found on devices, and the harness's phone in a bag is a model of what iOS does, not iOS itself.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| **Reproduction without the fix** | A scratch jj workspace at `1c93288c` with `MatchStore.swift` set back to `e2a2d14e`, plus only the test-only `quietGuestsAsked` counter. Then `swift test --package-path Packages/RekkertKit --filter QuietGuestTests` | fail, as intended | **Phones in a bag:** the 1.2 guest out of reach 10 times and the 1.1 guest 15 times, in 15 points. **Quiet break:** 4 and 1. The field's pattern: the 1.1 guest out of reach between every pair of points |
| **Reproduction with the fix** | `QuietGuestTests` on `1c93288c`, inside `scripts/verify.sh` | pass | All 3 tests (4 cases): nobody out of reach, with or without phones in a bag, and at most one ask per guest every 12 s |
| **Real absences still show** | `WhoIsOnTests` (`theHostSeesAGuestGoAndComeBack`, `aGuestOutOfRangeIsTheLinkBetweenItAndTheHost`), in the package run | pass | A guest that has gone is out of reach within 15 s |
| **Regression suite** | `scripts/verify.sh` | pass | 592 sync tests in 101 suites, 869 core tests, then 14 long simulations on their own (48 known issues). Then `tuist generate`, the iOS and watch app builds, and every plist assertion. 833 s |
| **FR-010's numbers in the long simulations** | The `BusyHall` / `ClubNight` lines printed in the same run | within the spread of runs on the old code | See below |
| **Lint / type-check** | Swift compiler warnings-as-built, and `verify.sh`'s `.nanoseconds(` check | pass | No new warnings in the changed files. The project has no separate linter |
| **Reproduction on devices** | The assessment's "On devices": a host on this build and a 1.1 guest with phones in bags, scoring every ~20 s for 10 min, then counting `guest … outOfReach` | not-run | Needs phones, a watch and a TestFlight build |

## Output Excerpts

Without the fix:

```text
Test guestsWithTheirPhonesInABagAreNeverOutOfReach() recorded an issue at QuietGuestTests.swift:62:9: Expectation failed: goneOutOfReach(on: court, since: start).isEmpty
  out of reach: guest1: 10, guest2: 15
Test aQuietBreakKeepsEveryoneInReachWithoutFloodingTheRadio() recorded an issue at QuietGuestTests.swift:72:9: Expectation failed: goneOutOfReach(on: court, since: start).isEmpty
  out of reach: guest1: 4, guest2: 1
Test run with 3 tests in 1 suite failed after 52.838 seconds with 2 issues.
```

With the fix, `scripts/verify.sh`:

```text
Test run with 592 tests in 101 suites passed after 62.795 seconds.
Test run with 869 tests in 75 suites passed after 0.730 seconds.
Test guestsWithTheirPhonesInABagAreNeverOutOfReach() passed after 16.769 seconds.
Test aQuietBreakKeepsEveryoneInReachWithoutFloodingTheRadio() passed after 6.549 seconds.
Test run with 14 tests in 8 suites passed after 730.957 seconds with 48 known issues.
==> All checks passed
exit 0 after 833 s
```

FR-010's numbers in that run, set against the runs on the old code recorded in `fix.md`:

| | This run | Old code |
|---|---|---|
| Busy hall, host p95 | 0.80 s | 0.75–0.91 s |
| Busy hall, guests' p95 | 1.25–1.77 s | 1.21–1.80 s |
| Busy hall, known issues | 18 | 14 in both runs |
| Club night, mean guest p95 | 3.17 s | 3.07 s and 6.32 s |
| Club night, host p95 | 1.02 s | 1.20–1.35 s |
| Club night, known issues | 30 | 30 and 40 |
| Club night, in step at every check | yes | |

- **The busy hall's 4 extra known issues** are FR-011's two checks on guest4's phone and watch. They arise because 5 of guest4's points arrived while something was wrong, which varies from run to run.
- **The busy hall's FR-010 numbers** are within the old code's spread.

## Residual Risks

- **Not seen on devices yet.** The harness's phone in a bag wakes for 10 s after each Bluetooth event and holds every timer meanwhile. iOS's real rules are looser, for example a watch's message also wakes its phone, and not documented exactly. The fix depends on the host's question waking a paused guest over Bluetooth, which is what `bluetooth-central` promises.
- **A real 1.1 phone was never run.** The 1.1 guest in the harness is this build's code with `actsAsOlderBuild`. The fix only relies on a 1.1 guest answering a hello, which every build since 1.0 does.
- **Club night varies a lot between runs** (3.1–7.3 s mean guest p95 over runs with and without the fix), so a small cost from the asks can't be ruled out from it. The host asked 5–17 times in a 30-minute night.
- **One club-night run in six failed `inStepAtEveryCheck`**: a run with the fix, sharing the machine with another simulation. It passed in every run since, including this one. Watch it on CI.
- **Records taken before the fix** still overstate absences: the summaries, calibration and arrival conditions read the false `outOfReach` entries.

## Recommendation

Keep the bug open until a game on real devices confirms it. Ship the fix in the next TestFlight build. At the next game with a guest on 1.1 or with phones in bags, count `guest … outOfReach` in the host's record, and compare each against the guest's own record. Expect near zero, apart from real walk-offs. If that holds, mark this bug verified. If the host still loses quiet guests, rerun `/speckit-bug-assess` with that game's records.
