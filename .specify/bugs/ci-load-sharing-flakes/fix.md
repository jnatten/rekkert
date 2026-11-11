# Bug Fix: Test and TestFlight runs fail since the steady-sharing branch loaded the runner with long court simulations

- **Slug**: ci-load-sharing-flakes
- **Fixed**: 2026-11-11
- **Assessment**: ./assessment.md
- **Status**: applied (verified locally; still to be confirmed on GitHub Actions)

## Summary

The package tests now run in two passes. Everything else runs in parallel first. Then the suites that hold the main actor for long stretches run one at a time: the court simulations that take minutes, plus the two-hour evening written to the record. All of them still run on every push and before every TestFlight upload. Separately, the watch stand-in now times its waits on the clock it is given, and the court harness hands it the radio's clock. Its waits and the stores' therefore come out in the same order however busy the machine is. Two expectations that fail even on an idle machine, `CalibrationFitTests.swift:68` and `BusyHallTests.swift:64`, now sit under the T059 known issue like the numbers beside them, as the user chose.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `scripts/package-tests.sh` | added | The first `swift test` pass skips the seven long suites. The second runs only them, with `--skip-build --no-parallel`. |
| `scripts/verify.sh` | modified | Calls `scripts/package-tests.sh` instead of `swift test`. |
| `scripts/release.sh` | modified | Same, so TestFlight runs the long suites too. |
| `README.md` | modified | *Verifying* names the script and says when a suite belongs on its list. |
| `Packages/RekkertKit/Sources/RekkertSync/WatchStandIn.swift` | modified | `init(…, now:, sleep:)`, defaulting to `ContinuousClock.now` and `Task.sleep`. The app's convenience init is unchanged. Every `ContinuousClock.now` and `.now` read and the run loop's sleep go through them. |
| `Packages/RekkertKit/Sources/RekkertSync/SharedSession.swift` | modified | `graceBeforeNotice` and `radioGrace` wait on the injected `sleep`, as `searchLimit`, `hostGrace` and `idleCheck` already did. Its default is `Task.sleep`, so the app is unchanged. |
| `Packages/RekkertKit/Tests/RekkertSyncTests/CourtHarness.swift` | modified | Gives each watch's `WatchStandIn` the radio clock (`monotonicClock`, `clockSleep`). The default `standInTick` goes from 100 ms to 1 s. The header comment now says the stand-in waits on the radio clock too. |
| `Packages/RekkertKit/Tests/RekkertSyncTests/CourtHarnessTests.swift` | added test | `aWatchStandingInWaitsInRadioTime` |
| `Packages/RekkertKit/Tests/RekkertSyncTests/GuestWristTests.swift` | modified | `court(ownWait:)`. `joiningAgainAfterTheHostStoppedSaysSoAndForgets` uses the app's own `ownWait` (20 s), which comes after the search's 14 s, as in the app. |
| `Packages/RekkertKit/Tests/RekkertSyncTests/CalibrationFitTests.swift` | modified | The 25 % p95 check is inside `withKnownIssue("…T059", isIntermittent: true)`. |
| `Packages/RekkertKit/Tests/RekkertSyncTests/BusyHallTests.swift` | modified | FR-011's 30 s check moves into the existing T059 `withKnownIssue` block beside the 5 s one. |

## Diff Highlights

```bash
# scripts/package-tests.sh
long='RekkertSyncTests\.(BusyHallTests|ClubNightTests|CalibrationFitTests|ClockOffsetTests|OlderHostTests|StandInDelayTests|LongEveningRecordTests)/'
swift test --package-path Packages/RekkertKit --skip "$long"
echo "==> Long court simulations, one at a time"
swift test --package-path Packages/RekkertKit --skip-build --no-parallel --filter "$long"
```

```swift
// WatchStandIn.swift
init(
    store: MatchStore, sharing: SharedSession, timing: StandInPolicy.Timing, tick: Duration,
    now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now },
    sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }
)

// CourtHarness.swift
let standIn = WatchStandIn(
    store: store, sharing: sharing, timing: timing.standIn, tick: timing.standInTick,
    now: monotonicClock, sleep: clockSleep
)
```

## Tests Added or Updated

- `CourtHarnessTests.aWatchStandingInWaitsInRadioTime` — a stand-in with a 3 s `ownWait` has not given up after 2 s of radio time and has by 4 s. It fails 2/2 when the harness leaves the stand-in on the machine's clock (checked in a scratch copy with the injection removed) and passes 3/3 with it.
- `GuestWristTests.joiningAgainAfterTheHostStoppedSaysSoAndForgets` — the order of the stand-in's own wait and the session's 14 s search is now explicit and matches the app's. Before, it held only while radio time ran about 30× faster than real time.
- `CalibrationFitTests.aRecordFromAKnownRadioIsFittedBackWithinAQuarter` and `BusyHallTests.everyDeviceGetsItsPointsInTime` — still run and print their numbers on every push. The two hard checks above are now known issues until T059.

## Local Verification

All on an M4 Pro (14 cores). "3-core proxy" means 11 busy loops running, leaving about three cores, roughly a hosted runner. "Heavy load" means 26 busy loops, the recipe from the assessment.

| Run | Result |
|---|---|
| `scripts/package-tests.sh`, idle, before the tick tuning | Parallel pass: 593 tests, **80 s**, all green (271 s on `main`, 888–1064 s for the branch on CI). One-at-a-time pass: green, but **998 s**, because 100 ms stand-in ticks on the radio clock defeat `skipsIdleTime`. |
| Same, with `standInTick` at 1 s | One-at-a-time pass: **612 s** (600 s before the clock change). `StandInDelayTests.swift:40` failed while its tick was 250 ms; it is back at 10 ms. `BusyHallTests.swift:64` failed once. |
| `BusyHallTests` + `StandInDelayTests` ×3, radio clock / `BusyHallTests` ×3, wall clock | Radio 3/3 green. Wall 2/3: one fail at `BusyHallTests.swift:64`. Together with CI's 1/6, the 30 s check was flaky before this fix, so per the user it is now a known issue. |
| Focused `GuestWrist|WatchStandIn|RelayedPoint|QuietChild` ×3, heavy load | `GuestWristTests` 0 failures in 3 (before the fix: `:40` 3/3, `:102–103` 1/3 on the old tree). `WatchStandInTests` and `QuietChildTests` still fail: they use their own fixtures on the machine's clock and failed the same way before the branch. |
| Parallel pass, 3-core proxy, ×3, before `LongEveningRecordTests` was moved | 4–5 failures each: `PerParticipantDeliveryTests.swift:141`, `OneRadioTests.swift:55–56`, `WatchStandInTests.swift:314`, plus one that varied. The unfixed tip under the same load: 7 and 15 failures (incl. `GuestWristTests.swift:40`). The pre-branch tree: only `GuestWristTests.swift:102–103`, 2/2. |
| Same, also skipping the branch's new suites | 1 one-off (`HostWatchSharingTests.swift:30`) in 2 runs. So the failures come from load added by a new suite, not from code changes. |
| Same, moving only `NoEcho`, `RecordPrivacy`, `OlderGuest`, `LinkChangeTraffic` out | No better (4–7 failures ×3), so these four are not the cause. |
| Same, moving only `LongEveningRecordTests` out (the final list) | ×2: one clean, one with the `HostWatchSharingTests.swift:30` one-off. |
| `HostWatchSharingTests` and the other stand-in suites, heavy load, radio vs wall clock | `:30` fails with **both** clocks, so it is load-sensitive regardless of this change. |
| Final `scripts/package-tests.sh`, idle | **Exit 0.** Parallel pass: 592 tests, 77 s, green. One-at-a-time pass: 11 tests in 7 suites, 683 s, green apart from the known issues. Wall time 763 s. |

## Deviations from Assessment

- **The long suites are not gated off; they run in their own pass.** The user wants them to run all the time. Instead of an opt-in environment variable, the script runs them in a second `swift test` pass, one at a time (`--no-parallel`), from both `verify.sh` and `release.sh`. No workflow change was needed.
- **`LongEveningRecordTests` is on the list.** The assessment only said to review it. Bisecting under the 3-core proxy showed it is what starves `OneRadioTests`, `PerParticipantDeliveryTests.swift:141` and `WatchStandInTests.swift:314`: it writes 1,200 points and then exports, parses and summarises the record on the main actor. "A forgotten share stops by itself" stays in the parallel pass, as it was on `main`.
- **The harness's default `standInTick` went from 100 ms to 1 s.** On the radio clock, a 100 ms tick per watch caps how far `skipsIdleTime` can jump, and made the one-at-a-time pass 66 % slower (998 s vs 600 s). 1 s is closer to the app's 2 s. It is still finer than what the stand-in effectively got before: 100 ms of real time was about 3 s of radio time on an idle machine. `StandInDelayTests` keeps its own 10 ms tick, because 250 ms made it fail.
- **`BusyHallTests.swift:64` and `CalibrationFitTests.swift:68` became known issues** (the assessment's third open question), on the user's decision. Both fail on an idle machine with either clock.
- **The budgets of `QuietChildTests`, `WatchStandInTests` and `OneRadioTests` were not widened.** With `LongEveningRecordTests` out of the parallel pass they pass under the 3-core proxy, as they did before the branch. They still use real-time budgets on their own fixtures and fail under heavy synthetic load.
- **FR-024 behaviour is unchanged.** The stand-in's own "not found" still keeps the code. The test now pins the app's order (20 s wait against the 14 s search) instead of depending on one.

## Follow-ups

- **Confirm on CI** (`/speckit-bug-test`): push the branch and run the Test workflow at least twice and TestFlight once. Expect the Test job to take about 25–30 minutes: the parallel pass ~3–4 minutes, the one-at-a-time pass maybe 15–20 on a hosted runner, plus the app builds. TestFlight should take about 35 minutes. Both are inside the 60-minute timeout. If that is too slow, the second pass can move to its own job in `test.yml`, which runs in parallel on a second runner.
- **Watch `HostWatchSharingTests.swift:30` on CI.** It failed once in a few runs under the 3-core proxy and under heavy load, with either clock. It waits 20 s of radio time for a guest to show as out of reach, which a lagging harness can miss.
- **Put the remaining real-time tests on test clocks**: `QuietChildTests` (`FanOutTransport` already takes `sleep`), the `Court` fixture in `WatchStandInTests` (now possible, since `WatchStandIn` takes `now`/`sleep`), `OneRadioTests` and `PerParticipantDeliveryTests`. Then a busy machine can't fail them at all.
- **FR-024:** decide whether the stand-in's own "not found" should also forget the kept code, so the outcome doesn't depend on its 20 s staying longer than the search's 14 s.
- **T059:** once the field run's record replaces the guessed radio speed, take the two checks back out of the known issue. Look into guest4's late FR-011 points in the busy hall (48–72 s on the wifi-only guest) as a bug of its own if they persist on calibrated speeds. The calibration fit itself is noisy (587 vs 3,308 B/s fitted for a known 3,000) and could average several replays per bisection step.
