# Bug Verification: A workout whose watch app is relaunched stops collecting heart rate and energy

- **Slug**: phone-start-no-heart-rate
- **Tested**: 2026-11-04
- **Assessment**: ./assessment.md
- **Fix**: ./fix.md
- **Result**: partial

## Summary

On the simulator the defect no longer reproduces. A workout whose watch app is killed and reopened goes on collecting heart rate and energy, live and in the saved workout, and nothing regressed. The result is **partial**, not verified, because the reporter's real-world case has not been exercised. That means a real watch on build 1.1 (74) with the fix, and whatever ended the app in their session, which remains unidentified.

## Checks Performed

Environment: the dedicated simulator pair. Apple Watch SE 3 (40 mm) on watchOS 26.0, paired with an iPhone 17 Pro on iOS 26.0, Apple Health access all granted. The watch app was the fixed build embedded in the iPhone app, the same code as the committed `591bad7`.

| Check | Command / Action | Result | Notes |
|-------|------------------|--------|-------|
| Reproduction (post-fix) | Start a workout on the watch. `simctl terminate` the watch app at 22:26:53, `simctl launch` at 22:26:56, then count healthd's builder statistics updates for 60 s | pass | "Beginning client recovery" at 22:26:57. Updates in the 60 s after reopening: heart rate 13, active energy 25, resting energy 25. Before the fix the same test gave 0 / 0 / 0 (assessment, Reproduction step 2). The scoreboard shows "♥ 60". |
| Saved workout after a recovery | Stop the recovered workout. On the phone: Home › Workouts › the 22:26 workout | pass | 3:17 long, total energy 3 kcal, average 59 bpm, highest 64, saved in Apple Health as tennis, indoor. The pre-fix recovered workout (21:34, 2:02 long) saved **0 kcal** total, because collection stopped at its kill 32 s in. |
| Collection without a relaunch | The same session before the kill: 4 heart-rate updates in the first 20 s; the scoreboard and workout page show a live BPM | pass | The start path is unchanged by the fix. |
| Background and back, same process | `HOME`, then `simctl launch` of the still-running app (PID 69945 throughout). Count updates for 40 s, and recoveries | pass | 9 heart-rate updates in 40 s. 0 "Beginning client recovery". `recover()` adopted nothing, as before the fix (assessment, step 3). |
| Regression suite | `scripts/verify.sh` at `591bad7` | pass | `==> All checks passed`: 495 + 790 package tests, both app builds, `MinimumOSVersion` 10.0, all plist and entitlement assertions. |
| Lint / type-check | The `xcodebuild` builds inside `verify.sh` | pass | No errors and no warnings. |
| On a real watch | Close Rekkert on the watch mid-workout and reopen it, on build 1.1 (74) | not-run | Build 74 was still processing on TestFlight when this was written. |
| The reported trigger | Close Rekkert on the watch, start from the phone, open Rekkert on the watch | not-run | The simulator cannot launch a closed watch app for a phone start (assessment, Reproduction step 4). Needs a real watch. |

## Output Excerpts

```text
killed at 2026-11-04 22:26:53
relaunched at 2026-11-04 22:26:56
HeartRate updates in the 60 s after relaunch: 13
ActiveEnergyBurned updates in the 60 s after relaunch: 25
BasalEnergyBurned updates in the 60 s after relaunch: 25
22:26:57.341 … HKLiveWorkoutBuilder_D873 [E7D2]: (#w0) Beginning client recovery

same process still alive: pid 69945
HR updates in the 40 s after coming back: 9
recovery adoptions when coming back: 0

􁁛  Test run with 495 tests in 74 suites passed after 52.651 seconds.
􁁛  Test run with 790 tests in 69 suites passed after 0.211 seconds.
  ok: "MinimumOSVersion" => "10.0"
==> All checks passed
```

## Residual Risks

- **No real watch yet.** The fix has not run on a real watch, or on watchOS 10 (the SE 1st generation). The recovery API is the same on watchOS 10, but it is unexercised there.
- **The trigger in the reported session is unknown.** There was no crash or jetsam log. With the fix, a relaunch costs only the gap before the app reopens. But if something ends the app repeatedly, each gap is lost.
- **Data from before a relaunch.** Samples nobody collected while the app was gone stay out of the workout, as HealthKit designs it.
- **The flat 0.18 kcal active-energy samples** in the reporter's Apple Health are still unexplained. The simulator generates almost no active energy, so it could not show whether active energy is right after a relaunch, only that it is collected again (25 updates).
- **Simulator quirk seen while testing,** not product behaviour. After a watch-app reinstall, healthd answered none of the app's requests until the simulator was restarted.

## Recommendation

Hold the bug open until the real-watch check. Install 1.1 (74) from TestFlight on the reporter's watch (and on the watchOS 10 one if possible), start a workout, close Rekkert from the watch's app switcher, reopen it, and confirm live heart rate returns and the saved workout's calories look right. While there, run the trigger test (close Rekkert on the watch, start from the phone), so step 2 of the assessment can be answered. If both pass, close the bug as verified.
