# Bug Verification: Test and TestFlight runs fail since the steady-sharing branch loaded the runner with long court simulations

- **Slug**: ci-load-sharing-flakes
- **Tested**: 2026-11-11
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: failed

## Summary

The fix (`d63cc440`) removed what the assessment found. `GuestWristTests` failed in all 6 attempts before; now it passes all 3 CI runs. The main parallel pass dropped from 888–1064 s to 242–255 s. But all three CI runs on the fixed commit still failed, all on `HostWatchSharingTests.swift:30`. **The fix itself introduced that failure.** With the stand-in now on the radio clock, a guest's watch stands in for its out-of-range phone after its 15 s `grace`. That is the same moment the host marks the guest out of reach after `Participant.quietLimit` (15 s). Which one lands first decides whether the host's watch ever sees "out of reach". One of the three runs also failed seven `WatchStandInTests` expectations and `RelayedPointTests.swift:163` in the first 30 s. Those tests wait in real time, and the fix doesn't touch their fixtures. Because the first pass failed every time, the one-at-a-time pass never ran on CI.

## Checks Performed

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction on CI: Test workflow, attempt 1 | push of `d63cc440` → run [43102627880](https://github.com/jnatten/rekkert/actions/runs/43102627880) | **fail** | Parallel pass 592 tests in 242 s, 9 issues: `HostWatchSharingTests.swift:30`, `WatchStandInTests.swift:179/184/187/221/566/573/574`, `RelayedPointTests.swift:163`. All within ~30 s of the start. |
| Reproduction on CI: TestFlight | dispatch on `d63cc440` → run [43102759108](https://github.com/jnatten/rekkert/actions/runs/43102759108) | **fail** | Parallel pass 592 tests in 255 s, 1 issue: `HostWatchSharingTests.swift:30`. Nothing was uploaded. |
| Reproduction on CI: Test workflow, attempt 2 | `gh run rerun 43102627880` | **fail** | Parallel pass 592 tests in 252 s, 1 issue: `HostWatchSharingTests.swift:30`. |
| The assessment's symptom: `GuestWristTests.swift:40/102–103` | the three CI runs above | pass | 0 of 3 runs, against 6 of 6 attempts before the fix (`:102–103`) and 5 of 6 (`:40`). |
| The assessment's local reproduction (26 busy loops, focused filter) | `swift test --skip-build --filter 'GuestWristTests\|WatchStandInTests\|RelayedPointTests'` ×2 | partial | `GuestWristTests` 0 failures in 2 runs, against `:40` 3/3 before. `WatchStandInTests` (5 and 9 issues) and `RelayedPointTests.swift:221` still fail, as they did on the pre-branch tree. |
| New and updated tests | `swift test --skip-build --filter 'CourtHarnessTests/aWatchStandingIn\|GuestWristTests'` ×3 at `d63cc440` | pass | 9 tests, 3/3 green. |
| Root cause of the new failure | scratch copy of `HostWatchSharingTests.theWatchIsToldWhatThePhoneIsSharing` tracing radio time from the guest phone walking away, ×3 idle | **confirmed** | Guest shown out of reach at 15.0 s and its watch standing in at 15.0 s, twice. In the third run the watch stood in first and the guest never showed as out of reach, even on an idle machine. |
| One-at-a-time pass on CI | `scripts/package-tests.sh` second pass | not-run | `set -e` stops after the first pass fails, so no CI run reached it. Its CI duration and the calibration and busy-hall known issues are unobserved there. Locally it passed: 683 s, exit 0. |
| Lint / type-check | — | not-run | The package has no separate lint step. The builds compile clean (Swift 6 language mode). |

## Output Excerpts

```
Test 43102627880 attempt 1
✘ Test aWatchWithNoPhoneJoinsTheHostItself() recorded an issue at WatchStandInTests.swift:179:9: Expectation failed: court.watch.role == .guest
✘ Test anAnswerIsHandedOnWithoutWaitingForAChildThatNeverAnswers() recorded an issue at RelayedPointTests.swift:163:9: Expectation failed: heardAfter < .seconds(2)
✘ Test theWatchIsToldWhatThePhoneIsSharing() recorded an issue at HostWatchSharingTests.swift:30:9: Expectation failed: await court.until(within: .seconds(20)) {
✘ Test run with 592 tests in 100 suites failed after 241.991 seconds with 9 issues.

TestFlight 43102759108
✘ Test theWatchIsToldWhatThePhoneIsSharing() recorded an issue at HostWatchSharingTests.swift:30
✘ Test run with 592 tests in 100 suites failed after 254.579 seconds with 1 issue.

Test 43102627880 attempt 2
✘ Test theWatchIsToldWhatThePhoneIsSharing() recorded an issue at HostWatchSharingTests.swift:30
✘ Test run with 592 tests in 100 suites failed after 252.204 seconds with 1 issue.

Trace (scratch copy, idle)
TRACE outOfReach at Optional(15.0 seconds), guest watch standing in at Optional(15.0 seconds)
TRACE outOfReach at Optional(15.0 seconds), guest watch standing in at Optional(15.0 seconds)
TRACE outOfReach at nil, guest watch standing in at Optional(15.0 seconds)
```

## Residual Risks

- **`HostWatchSharingTests.swift:30` is a tie the fix exposed, not a load flake.**
  - The test takes only the guest's phone out of range (`HostWatchSharingTests.swift:28`). The guest's watch stays in reach.
  - On the machine's clock the watch's 15 s `grace` never ran out within the test. On the radio clock it runs out exactly when the host's 15 s `quietLimit` does.
  - The same tie exists in the app: both are 15 s. A guest whose phone drops out while its watch is in reach may or may not show as out of reach on the host, depending on which side acts first. That may be the intended behaviour (the watch is standing in, so the guest is still on), but nothing pins it down.
- **The startup crunch still bites real-time tests.**
  - Attempt 1's eight other failures happened in the first 30 s, when all 100 suites start at once on the main actor.
  - `WatchStandInTests`' own `Court`, `QuietChildTests`, `OneRadioTests` and `PerParticipantDeliveryTests` budget real time (2–5 s).
  - On `main` they passed beside a similar total load. One run in three is too few to say whether the branch's new short suites raised the odds.
- **The one-at-a-time pass is unproven on CI**: neither its length on a hosted runner (estimated 15–20 minutes) nor its known-issue handling has run there.

## Recommendation

Reopen. The original symptom (Test and TestFlight fail on every run) still reproduces on CI, and part of it is now a failure this fix introduced. Re-run `/speckit-bug-assess` with this report, or go straight to another `/speckit-bug-fix` round. In order:

1. **Break the tie in `HostWatchSharingTests.theWatchIsToldWhatThePhoneIsSharing`.** Take the guest's watch out of range with its phone (`court.outOfRange(court.guests.first!.watch!)`). The test is about the host's wrist hearing that a guest is gone. Whether a stand-in should keep a guest "on" at the 15 s mark is a product question about FR-019/FR-010 to settle separately.
2. **Sweep for other tests that relied on the stand-in never standing in.** Look at any suite where a phone goes out of range or is ended while its watch stays in reach, with default stand-in timing for longer than 15 s of radio time. None failed in four local runs or on CI apart from this one, but CI has not yet run the one-at-a-time pass.
3. **Take the startup crunch off the real-time fixtures.** Give `WatchStandInTests`' `Court` and `QuietChildTests` the injected clocks that `WatchStandIn` and `FanOutTransport` now accept. Alternatively, cap the first pass's parallelism, and check first whether `swift test --num-workers` limits Swift Testing.
4. Then confirm on CI with two Test runs and one TestFlight run, and check how long the one-at-a-time pass takes there.
