# Bug Fix: A workout whose watch app is relaunched stops collecting heart rate and energy

- **Slug**: phone-start-no-heart-rate
- **Fixed**: 2026-11-04
- **Assessment**: ./assessment.md
- **Status**: partial. Step 1 of the preferred remediation is applied and verified. Step 2 (finding what ended the process in the reported session) needs the reporter's watch and is open.

## Summary

When the watch app's process ends mid-workout and is relaunched, `recover()` adopts the running session but never gave its builder a data source. HealthKit ends the old data source along with the dead process, so nothing more reached Rekkert. Now a recovered builder without a data source gets the same one `begin()` sets up, from the recovered session's own configuration, and collection resumes at the moment of relaunch.

## Changes

| File | Change | Notes |
|------|--------|-------|
| `WatchApp/Sources/WorkoutController.swift` | modified | New `collect(into:for:)` builds the `HKLiveWorkoutDataSource` (tennis defaults plus resting energy). `begin()` calls it in place of its inline setup. `recover()` calls it after `attach(_:)` when the adopted builder has no data source. The comment in `recover()` that said collection "has been going the whole time" is corrected. |

## Diff Highlights (optional)

```swift
// recover()
attach(recovered)
if let builder, builder.dataSource == nil {
    collect(into: builder, for: recovered.workoutConfiguration)
}

// begin()
attach(session)
guard let builder else { return }
collect(into: builder, for: Self.configuration)
```

## Tests Added or Updated

- None automated. The watch app has no test target, and the change is the HealthKit wiring in the app shell, with no rule to lift into `RekkertCore`. It is verified on the simulator below, by the same reproduction that showed the bug.

## Local Verification

Simulators: Apple Watch SE 3 (40 mm) on watchOS 26.0, paired with an iPhone 17 Pro on iOS 26.0. Apple Health access all granted. The build was the iPhone app with the watch app embedded, at `5cf1a77` plus this change.

- **The reproduction, before the fix** (assessment, step 2):
  - Kill the app at 21:34:36, reopen at 21:34:39.
  - The heart shows no number, and the workout page reads "— — BPM".
  - Builder statistics updates from the relaunch until the workout ended: **0** for heart rate, **0** for active energy, **0** for resting energy.
- **The same reproduction, after the fix:**
  - Start a workout. At 0:22 it shows 62 BPM, average 62, highest 64.
  - Kill the app at 21:58:52 and reopen it at 21:58:56. healthd again logs `HDWorkoutBasicDataSource: … stopping collection on connection invalidation` / "Ending collection".
  - About 40 s later the scoreboard reads "♥ 64", and the workout page shows 57 BPM at 1:29, average 60, highest 64.
  - Builder statistics updates since the relaunch: **10** for heart rate, **20** for active energy, **20** for resting energy.
  - The workout then stopped and saved normally (effort question shown).
- **Control, a workout that is never killed:** the start path is unchanged, and collection was as before (62 BPM before the kill).
- **`scripts/verify.sh`** → `==> All checks passed`. 495 + 790 package tests, both app builds, `MinimumOSVersion` 10.0, no warnings.
- **A simulator problem along the way, not caused by the change.** After the watch app was reinstalled over the old one, no Apple Health request from it reached healthd (healthd logged "Ignoring LaunchServices notification for placeholder"), so no workout could start by any route. Restarting the watch simulator cleared it. The start path never reaches the new code (`collect` is only called once a session exists).

## Deviations from Assessment

- **The data source is built from the recovered session's `workoutConfiguration`**, not from `Self.configuration`, as Apple's sample does. Rekkert only ever starts sessions with `Self.configuration`, so the two are the same in practice. The session's own value stays right if that ever changes.
- **No `dataSource == nil` guard in `begin()`.** A builder `begin()` has just created never has one. The guard is only in `recover()`, where the assessment asked for it.

## Follow-ups

- **Find what ended the watch app in the reported session** (assessment step 2). There was no crash or jetsam log on the reporter's iPhone. Device test: close Rekkert on the watch, start from the phone, then open Rekkert on the watch. With this fix the workout keeps collecting either way, but a phone start that silently loses its process is still worth knowing about. The simulator cannot launch a closed watch app in the background, so this needs a real watch.
- **Data from before a relaunch is still lost.** HealthKit hands it to nobody once the old data source is gone. That is a platform limit; the fix keeps the loss to the gap.
- **The flat 0.18 kcal active-energy samples** in the reporter's Apple Health are still unexplained. They were not reproduced on the simulator.
- **The smaller issue from the assessment's first revision:** a watch that has never been through its own Apple Health sheet can begin a phone-started workout on the iPhone's grant alone. It is separate from this fix.
- **Ship it before 1.1 goes to App Review.** Build 73 on TestFlight has the bug.
