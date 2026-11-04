# Bug Assessment: A workout whose watch app is relaunched stops collecting heart rate and energy

- **Slug**: phone-start-no-heart-rate (named before reproduction; the start path turned out not to be the cause)
- **Created**: 2026-11-04 (revised twice the same day: once with the reporter's Apple Health data, once with a simulator reproduction)
- **Source**: pasted text, plus answers, two screenshots and a reproduction in the session
- **Verdict**: valid. The defect is reproduced. The trigger in the reported session is not yet identified.
- **Severity**: high

## Report (verbatim or summarized)

> after the previous changes where we support older watchos we now have a bug where workouts arent tracked correctly.
>
> We were a bunch of people where only two of us had the newest testflight version with the watchos 10 support which only the two of us the workout failed to record our heartrate and the calories ended up _way_ below what was expected. (70 instead of probably something around 1000).

Answers and evidence given afterwards:

- **How it was started.** "i pressed the phone first with no start, then i pressed the watch. not 100% sure but i think the other person started on the watch only."
- **Watches.** One watchOS 10 watch, one newer one. The workout examined was on **the newer one**.
- **What showed.** "it did not show up during the workout in the top left nor on the workout screen. but i can see the graph in the fitness app now."
- **Apple Health access.** All on (the iPhone's Health app, Sources › Apps › Rekkert), and believed to have been on throughout.
- **Heart rate in Health, about 17:55–19:30.** Samples from the watch several times a minute, 138–153 bpm. The watch was measuring as in a workout.
- **Active energy in Health.** Samples from the watch for the whole session, each exactly 0.18 kcal, a few seconds apart. They are flat, where energy that follows a heart rate near 145 bpm would vary.
- **Rekkert's "70"** is the saved workout's active energy (`Shared/WorkoutFormat.swift:45`).

## Symptom

A workout is running on the watch, and the watch measures heart rate at workout rate. But Rekkert shows no live heart rate (neither the scoreboard glyph nor the workout page), and the workout it saves has no heart-rate statistics and far too little energy. Expected: live heart rate, and a saved workout with the heart rate and energy the watch measured.

## Reproduction

Reproduced on the simulator pair made for feature 003: Apple Watch SE 3 (40 mm) on watchOS 26.0, paired with an iPhone 17 Pro on iOS 26.0. The watch app's workout code is identical to build 73's. Apple Health access was all granted on the watch's own sheet.

1. **Control.** Start a workout on the watch. After 21 s the workout page shows 56 BPM, an average of 58 and a highest of 61. HealthKit logs builder statistics updates for heart rate, active and resting energy every few seconds (5 / 11 / 11 in the first half minute).
2. **End the watch app's process mid-workout** (`simctl terminate`, as watchOS does to a crashed or jetsammed app), and open it again 3 s later.
   - healthd logs "Connection invalidated", `HDWorkoutBasicDataSource: Ending collection` for heart rate, active energy, resting energy and distance, then "Basic data source deallocated".
   - On relaunch: "Beginning post-client-crash recovery" and the builder's "Beginning client recovery". Rekkert's `recover()` adopts the session. The scoreboard shows the heart with **no number**, and the workout page reads "— — BPM" with no energy, average or highest.
   - From then until the workout ended about 1.5 minutes later: **zero** builder statistics updates for any type.
3. **Control 2.** Start a new workout and send the app to the background (Home) without ending its process, then bring it back. Collection carries on (61 BPM at 0:54, average 61, highest 64). `recover()` ran twice here (from `start()` and `becameActive()`). Each time Health handed back an object in **NotStarted**, because the original connection was alive, and the guard skipped it.

4. **Phone start with the watch app closed.** The phone app was launched with `-rekkert-demo-workout-follow ask` (which sets `pretendsAvailable`, as in `.specify/bugs/phone-workout-start-slow/test.md`). Tapped Home › Start a workout at 21:45:55.
   - The phone's HealthKit logged "Starting workout app dev.natten.rekkert on watch".
   - The watch's healthd logged "received incoming Start Workout App request" at 21:45:56.278.
   - The simulator never launched the closed watch app: it was still not running 30 s later, and the phone sat on "Waiting for your Apple Watch".
   - **This path cannot be exercised on the simulator.** Whether a real watch's background launch for a phone start can end its process before reporting, and so leave the next open to recover, needs a device.

This is the reporter's symptom: live heart rate missing on the wrist, and a saved workout without heart rate. It needs nothing build-73-specific except whatever ended the process (see Open Questions). The flat 0.18 kcal samples are not reproduced on the simulator.

## Suspected Code Paths

- `WatchApp/Sources/WorkoutController.swift:203` `recover()` → `:393` `attach(_:)`. It adopts the recovered session and its `associatedWorkoutBuilder()` and sets their delegates, but **never gives the builder a data source**. The data source lives with the app's connection (healthd deallocates it when the process dies, as above). So a recovered builder collects nothing. Apple's WWDC25 sample and the forum code set a fresh `HKLiveWorkoutDataSource` on a recovered builder ([WWDC25 322](https://developer.apple.com/la/videos/play/wwdc2025/322/?time=574), [forum 764691](https://developer.apple.com/forums/thread/764691)).
- `WatchApp/Sources/WorkoutController.swift:363` `begin()` (`:376–382`). The only place a data source is built.
- `Shared/AppModel.swift:208` (`start()`) and `:718` (`becameActive()`) call `recover()`. Harmless while this process holds the session (step 3), so the recovery after a relaunch is the only failing case.

Ruled out:

- **Apple Health permissions.** Full access, and a workout that measured heart rate.
- **A race between `recover()` and a phone start's `begin()`** (the previous revision's hypothesis). Step 3 shows Health returns a NotStarted object while the original connection lives, so `recover()` never adopts a session its own process holds.
- **The watchOS 10 changes, the `Mutex` → `OSAllocatedUnfairLock` swap, and the sync change.** None of them is on the collection path.

## Root Cause Hypothesis

`recover()` was written for a relaunch after the app was killed mid-workout, but it leaves the recovered builder with no data source. HealthKit ends the old data source along with the dead process, so from the moment of relaunch the session runs, and the sensors measure, but nothing reaches Rekkert's builder. There is no live heart rate, and the saved workout lacks heart rate and most of its energy. **Confidence: high** for the defect (reproduced, and confirmed in healthd's log). **Medium** that it explains the reported session. That requires the watch app's process to have ended near the start of that workout, which is not yet confirmed. If it was a crash, it may be new in build 73, which would explain why only build 73 testers were affected.

## Proposed Remediation

**Preferred**:

1. **Give a recovered builder a data source.** Factor the setup out of `begin()` (an `HKLiveWorkoutDataSource` for `Self.configuration`, plus `enableCollection` for resting energy) into one helper. Call it from `begin()`, and from `recover()` after `attach(_:)` when it adopts a running or paused session, as Apple's sample does. Collection resumes at the moment of relaunch, and the readings and the saved workout cover everything after it.
2. **Find what ended the process in the reported session**, and fix it if it is a crash (see Open Questions). Step 1 makes a relaunch harmless to the data from that point on, but the gap before the relaunch is still lost.

**Alternatives** (optional):

- **Restart collection on a new session after a recovery** (end the recovered one, begin a fresh one). Rejected: it splits one workout into two in Apple Health.

**Files likely to change**:

- `WatchApp/Sources/WorkoutController.swift` (`begin()`, `recover()`, a new data-source helper)

**Tests to add or update**:

- There is no app test target. Verify on the simulator by repeating the reproduction above.
  - After a relaunch, the workout page shows a live heart rate within about 10 s, and HealthKit logs statistics updates again.
  - The saved workout's average heart rate and energy cover the time after the relaunch.
  - Controls 1 and 3 still pass.
- Verify on a real watch, ideally the watchOS 10 one too. Start, then end Rekkert's process from the app switcher, reopen, and check the same things.

## Risks & Considerations

- **Data before the relaunch is not recovered.** Samples the old data source never handed over stay out of the workout. That is HealthKit's design, and step 1 limits the loss to the gap.
- **Don't set a second data source on a builder that has one** (`builder.dataSource == nil` check), so a recover that adopts after a real relaunch is the only path that adds one.
- **Wrong data already in Apple Health.** Testers' affected workouts keep their low calories. They can delete them in Fitness.
- **Release timing.** Build 73 is TestFlight only. Ship step 1 before 1.1 goes to App Review.
- **A separate, smaller issue from the first revision still stands.** A watch that has never been through its own Apple Health sheet can begin a phone-started workout on the iPhone's grant alone. See this file's history. It is not what happened here.

## Open Questions

- Answered: no `RekkertWatch-…` or `JetsamEvent-…` entries on the reporter's iPhone for the session. So the process did not end in a logged crash or memory kill. That leaves a hand close, or watchOS ending the phone-start background launch without a log.
- [NEEDS CLARIFICATION: Device test for the remaining trigger. Close Rekkert on the watch, start from the phone, then open Rekkert on the watch. Does it show a running workout with no heart rate? If so, the phone-start background launch is the trigger.]
- [Superseded: Did Rekkert's watch app end or restart during or just after the start of the reported workout? Look on the iPhone under Settings › Privacy & Security › Analytics & Improvements › Analytics Data (*Personvern og sikkerhet › Analyse og forbedringer › Analysedata*) for entries named `RekkertWatch-2026-11-04-…` (a crash) or `JetsamEvent-2026-11-04-…` (killed for memory), from about 17:50 to 18:00. A crash log gives the code to fix next.]
- [NEEDS CLARIFICATION: Was Rekkert closed from the watch's app switcher, and reopened, after the phone start "did nothing"? That alone would cause this.]
- [NEEDS CLARIFICATION: The watchOS 10 tester's session: same symptom from a watch start. Any crash or jetsam entry on their phone?]
- [NEEDS CLARIFICATION: Why the watch's own energy samples are flat at 0.18 kcal. Not reproduced on the simulator. Possibly how watchOS estimates energy for a running session with no client data source.]
